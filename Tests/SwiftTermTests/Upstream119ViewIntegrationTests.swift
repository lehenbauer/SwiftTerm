//
//  Upstream119ViewIntegrationTests.swift
//
//  Behavior tests for how upstream v1.19 view features (SGR 5 text blink,
//  backgroundOpacity, DECSCNM reverse screen) compose with the fork's view
//  contracts: the line-info cache that both renderers read, the CG
//  scrolled-back repaint skip, and the appearance/theme API.
//
//  Every blink test drives the phase change through production code — either
//  the `setTextBlinkVisibleForTesting` hook or the real blink `Timer` fired
//  synchronously — and then observes what the renderers actually consume. On
//  v1.99.2 that is the frame snapshot built through the view's own
//  `SnapshotTextBuilder` (whose attribute cache replaced the fork's line-info
//  cache), CG pixels after a frame tick, CG invalidation rects from a frame
//  tick, and Metal draw data compared with a from-scratch rebuild. A build
//  through a fresh text builder is used only as the control proving the phase
//  really is hidden.
//
#if os(macOS)
import AppKit
import Foundation
import Testing
#if canImport(MetalKit)
import Metal
#endif

@testable import SwiftTerm

/// Records the rects `updateDisplay` / invalidation code asks AppKit to repaint.
private final class BlinkInvalidationCapturingView: TerminalView {
    var invalidated: [NSRect] = []

    override func setNeedsDisplay(_ invalidRect: NSRect) {
        invalidated.append(invalidRect)
        super.setNeedsDisplay(invalidRect)
    }
}

private let esc = "\u{1b}"
/// Blink + underline + strikethrough on a blue background, then a plain tail.
private let blinkLine = "\(esc)[5;4;9;44mBLINK\(esc)[0m tail"

private var reduceMotion: Bool {
    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
}

#if canImport(MetalKit)
private var hasMetal: Bool { MTLCreateSystemDefaultDevice() != nil }
#endif

private struct RGBA: Equatable, CustomStringConvertible {
    let r: Int, g: Int, b: Int, a: Int

    init(_ color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? color
        r = Int((c.redComponent * 255).rounded())
        g = Int((c.greenComponent * 255).rounded())
        b = Int((c.blueComponent * 255).rounded())
        a = Int((c.alphaComponent * 100).rounded())
    }

    init?(_ color: CGColor?) {
        guard let color, let ns = NSColor(cgColor: color) else { return nil }
        self.init(ns)
    }

    var rgb: [Int] { [r, g, b] }
    var description: String { "rgb(\(r),\(g),\(b)) a=\(a)%" }
}

@MainActor
@Suite(.serialized)
final class Upstream119ViewIntegrationTests {

    // MARK: - Helpers

    /// The current frame snapshot and the render context the renderers use.
    private func frameSnapshot(_ view: TerminalView) -> (TerminalSnapshot, SnapshotRenderContext) {
        let snapshot = TerminalSnapshot()
        let viewState = FrameViewState(view: view)
        view.withTerminal { terminal in
            _ = snapshot.refresh(terminal: terminal, viewState: viewState,
                                 selection: SnapshotSelectionState(selection: view.selection))
        }
        return (snapshot, SnapshotRenderContext(viewState: viewState, snapshot: snapshot))
    }

    private func firstCell(_ view: TerminalView, row: Int, builder: SnapshotTextBuilder)
        -> (text: String, attributes: [NSAttributedString.Key: Any])?
    {
        let (snapshot, context) = frameSnapshot(view)
        let index = row - snapshot.firstRow
        guard index >= 0, index < snapshot.rows.count else { return nil }
        let info = builder.buildAttributedString(row: snapshot.rows[index], absoluteRow: row,
                                                 context: context)
        guard let segment = info.segments.first(where: { $0.column == 0 }),
              segment.attributedString.length > 0 else { return nil }
        return (segment.attributedString.string,
                segment.attributedString.attributes(at: 0, effectiveRange: nil))
    }

    /// The first rendered segment of `row` as the CG renderer builds it,
    /// through the view's long-lived text builder and its attribute cache.
    private func cachedFirstCell(_ view: TerminalView, row: Int)
        -> (text: String, attributes: [NSAttributedString.Key: Any])?
    {
        firstCell(view, row: row, builder: view.textBuilder)
    }

    /// Same as `cachedFirstCell` but through a fresh builder (the control).
    private func freshFirstCell(_ view: TerminalView, row: Int)
        -> (text: String, attributes: [NSAttributedString.Key: Any])?
    {
        firstCell(view, row: row, builder: SnapshotTextBuilder())
    }

    /// Runs main-queue work the terminal callbacks queued (`onMain`). A
    /// nested run loop cannot do this: the test itself runs on the main queue.
    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private func reverseColors(_ view: TerminalView) -> Bool {
        view.withTerminal { $0.reverseColors }
    }

    /// Hosts `view` in a window and makes the blink lifecycle eligible to run a
    /// real timer. Returns the window so the caller keeps it alive.
    private func hostForBlinking(_ view: TerminalView) -> NSWindow {
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.contentView = view
        view.textBlinkApplicationActive = true
        view.updateTextBlinkLifecycle()
        return window
    }

    private func render(_ view: TerminalView) -> Data? {
        // Drawing reads the frame snapshot; refresh it first.
        view.frameTick()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let base = rep.bitmapData else { return nil }
        return Data(bytes: base, count: rep.bytesPerRow * rep.pixelsHigh)
    }

    private func rowBand(_ view: TerminalView, screenRow: Int) -> (bottom: CGFloat, top: CGFloat) {
        let cellHeight = view.cellDimension.height
        let bottom = view.frame.height - CGFloat(screenRow + 1) * cellHeight
        return (bottom, bottom + cellHeight)
    }

    // MARK: - (1) Blink phase through the line-info cache (A3)

    /// Control: the hook really produces the hidden phase for a fresh build,
    /// and the visible phase renders glyph + decorations. Guards the red tests
    /// below against a false failure from a phase that never changed.
    @Test func blinkHookHiddenPhaseIsObservableWithoutCache() throws {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 120))
        view.feed(text: blinkLine)
        let visible = try #require(freshFirstCell(view, row: 0))
        #expect(visible.text.first == "B")
        #expect(visible.attributes[.underlineStyle] != nil)
        #expect(visible.attributes[.strikethroughStyle] != nil)

        view.setTextBlinkVisibleForTesting(false)
        #expect(view.textBlinkVisible == false)
        let hidden = try #require(freshFirstCell(view, row: 0))
        #expect(hidden.text.first == " ")
        #expect(hidden.attributes[.backgroundColor] != nil)
        #expect(hidden.attributes[.underlineStyle] == nil)
        #expect(hidden.attributes[.strikethroughStyle] == nil)
    }

    /// Warm the renderer's text builder in the visible phase, toggle hidden
    /// with the hook: what the renderers read must be the hidden phase.
    /// (The fork's neighbor-row cache-retention checks have no v1.99.2
    /// counterpart: the CG text builder has no per-row cache, and a blink
    /// phase change is a frame-style change that repaints the view.)
    @Test func blinkHookToggleIsVisibleThroughCachedLineInfo() throws {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 120))
        view.feed(text: "plain neighbor\r\n" + blinkLine)
        let blinkRow = 1, neighborRow = 0

        let warm = try #require(cachedFirstCell(view, row: blinkRow))
        #expect(warm.text.first == "B")
        let neighborBefore = try #require(cachedFirstCell(view, row: neighborRow))

        view.setTextBlinkVisibleForTesting(false)
        #expect(view.textBlinkVisible == false)

        let hidden = try #require(cachedFirstCell(view, row: blinkRow))
        #expect(hidden.text.first == " ", "cachedLineInfo served stale blink phase: \(hidden.text.debugDescription)")
        #expect(hidden.attributes[.backgroundColor] != nil)
        #expect(hidden.attributes[.underlineStyle] == nil, "stale underline in hidden phase")
        #expect(hidden.attributes[.strikethroughStyle] == nil, "stale strikethrough in hidden phase")

        // The neighbor row's rendering is unaffected by the phase.
        let neighborAfter = try #require(cachedFirstCell(view, row: neighborRow))
        #expect(neighborAfter.text == neighborBefore.text)

        // And back to visible.
        view.setTextBlinkVisibleForTesting(true)
        let back = try #require(cachedFirstCell(view, row: blinkRow))
        #expect(back.text.first == "B")
        #expect(back.attributes[.underlineStyle] != nil)
    }

    /// Same contract through the production timer: fire the real blink timer
    /// synchronously (no sleep) and read the cache.
    @Test(.enabled(if: !reduceMotion, "Reduce Motion disables the blink timer"))
    func blinkTimerToggleIsVisibleThroughCachedLineInfo() throws {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 120))
        view.feed(text: "plain neighbor\r\n" + blinkLine)
        let window = hostForBlinking(view)
        defer { window.contentView = nil }
        let timer = try #require(view.textBlinkTimer, "blink timer must start for a hosted, active view")
        #expect(view.textBlinkVisible)

        let warm = try #require(cachedFirstCell(view, row: 1))
        #expect(warm.text.first == "B")
        let neighborBefore = try #require(cachedFirstCell(view, row: 0))

        timer.fire()
        #expect(view.textBlinkVisible == false, "timer fire must hide")
        #expect(view.textBlinkTimer === timer, "phase must not be reset by the lifecycle")

        let hidden = try #require(cachedFirstCell(view, row: 1))
        #expect(hidden.text.first == " ", "cachedLineInfo served stale blink phase: \(hidden.text.debugDescription)")
        #expect(hidden.attributes[.underlineStyle] == nil, "stale underline in hidden phase")
        #expect(cachedFirstCell(view, row: 0)?.text == neighborBefore.text, "non-blink neighbor unaffected")
    }

    /// CG pixels: a view whose cache was warmed in the visible phase and then
    /// toggled hidden must draw exactly what a cold view in the hidden phase
    /// draws. Control: hidden and visible frames differ.
    @Test func blinkHiddenPhaseCGPixelsMatchColdRender() throws {
        func makeView() -> TerminalView {
            let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 120))
            view.feed(text: "plain neighbor\r\n" + blinkLine + "\(esc)[?25l")
            return view
        }
        let warmed = makeView()
        let visiblePixels = try #require(render(warmed))
        warmed.setTextBlinkVisibleForTesting(false)
        let warmedHiddenPixels = try #require(render(warmed))

        let cold = makeView()
        cold.setTextBlinkVisibleForTesting(false)
        let coldHiddenPixels = try #require(render(cold))

        #expect(coldHiddenPixels != visiblePixels, "control: hidden phase must change pixels")
        #expect(warmedHiddenPixels == coldHiddenPixels, "CG drew a stale blink phase from the warm cache")
    }

    // MARK: - (2) Blink invalidation while scrolled back on CG (A4)

    /// Builds a hosted CG view whose blink line sits at viewport row
    /// `screenRow` while scrolled to the top of a deep scrollback.
    private func makeDeepScrolledBackBlinkView(screenRow: Int, hosted: Bool)
        -> (BlinkInvalidationCapturingView, NSWindow?)
    {
        let view = BlinkInvalidationCapturingView(frame: CGRect(x: 0, y: 0, width: 640, height: 320))
        let rows = view.terminalDimensions.rows
        for i in 0..<screenRow { view.feed(text: "pre \(i)\r\n") }
        view.feed(text: blinkLine + "\r\n")
        for i in 0..<(rows * 3) { view.feed(text: "line \(i)\r\n") }
        let window = hosted ? hostForBlinking(view) : nil
        view.frameTick()
        view.scrollTo(row: 0)
        view.frameTick()
        view.withTerminal { $0.clearUpdateRange() }
        view.invalidated.removeAll()
        return (view, window)
    }

    /// Control for the helper: a highlight change on the blink row's viewport
    /// row (the hover path) schedules a frame that repaints that band, without
    /// a live-screen core mark.
    @Test func scrolledBackViewportRowControlHitsBand() {
        let screenRow = 2
        let (view, _) = makeDeepScrolledBackBlinkView(screenRow: screenRow, hosted: false)
        let buffer = view.terminal.buffer
        #expect(buffer.yBase - buffer.yDisp >= view.terminal.rows)
        #expect(view.visibleBlinkRows() == [buffer.yDisp + screenRow])
        let range = [Terminal.LinkMatch.RowRange(row: buffer.yDisp + screenRow, range: 0..<5)]
        view.linkHighlightRange = range
        view.invalidateLinkHighlight(oldRange: nil, newRange: range)
        #expect(view.withTerminal { $0.getUpdateRange() } == nil)
        view.frameTick()
        let band = rowBand(view, screenRow: screenRow)
        #expect(view.invalidated.contains { $0.minY <= band.bottom && $0.maxY >= band.top })
    }


    /// Real timer path: deep scrolled back, fire the blink timer, run one
    /// display tick. The blink row's viewport band must be invalidated.
    @Test(.enabled(if: !reduceMotion, "Reduce Motion disables the blink timer"))
    func blinkTimerWhileDeepScrolledBackInvalidatesViewportRow() throws {
        let screenRow = 2
        let (view, window) = makeDeepScrolledBackBlinkView(screenRow: screenRow, hosted: true)
        defer { window?.contentView = nil }
        let buffer = view.terminal.buffer
        #expect(buffer.yBase - buffer.yDisp >= view.terminal.rows)
        #expect(view.visibleBlinkRows() == [buffer.yDisp + screenRow])
        let timer = try #require(view.textBlinkTimer, "blink timer must be running")
        // Warm the cache the way a prior draw of the visible phase would.
        #expect(cachedFirstCell(view, row: buffer.yDisp + screenRow)?.text.first == "B")

        timer.fire()
        #expect(view.textBlinkVisible == false)
        view.frameTick()
        #expect(view.textBlinkVisible == false, "setup: display tick must not reset the phase")

        let band = rowBand(view, screenRow: screenRow)
        let repainted = view.invalidated.contains { $0.minY <= band.bottom && $0.maxY >= band.top }
        #expect(repainted, "blink toggle while scrolled back invalidated \(view.invalidated); row band [\(band.bottom), \(band.top)]")

        // What the next draw would read for that row must be the hidden phase.
        let hidden = try #require(cachedFirstCell(view, row: buffer.yDisp + screenRow))
        #expect(hidden.text.first == " ", "scrolled-back blink row cached in stale phase")
    }

    /// The test hook uses the production blink-row invalidation path.
    /// Unhosted, so the next display tick's lifecycle resets the phase to
    /// visible — that reset re-invalidates the same rows, so the band must
    /// still be repainted.
    @Test func blinkHookWhileDeepScrolledBackInvalidatesViewportRow() {
        let screenRow = 2
        let (view, _) = makeDeepScrolledBackBlinkView(screenRow: screenRow, hosted: false)
        view.setTextBlinkVisibleForTesting(false)
        view.frameTick()
        let band = rowBand(view, screenRow: screenRow)
        let repainted = view.invalidated.contains { $0.minY <= band.bottom && $0.maxY >= band.top }
        #expect(repainted, "blink hook while scrolled back invalidated \(view.invalidated); row band [\(band.bottom), \(band.top)]")
    }

    /// Control: pinned to the bottom, the same timer path does hit the row,
    /// proving the scrolled-back failure is the live-space/viewport mismatch.
    @Test(.enabled(if: !reduceMotion, "Reduce Motion disables the blink timer"))
    func blinkTimerPinnedInvalidatesRow() throws {
        let view = BlinkInvalidationCapturingView(frame: CGRect(x: 0, y: 0, width: 640, height: 320))
        view.feed(text: "a\r\nb\r\n" + blinkLine + "\r\n")
        let window = hostForBlinking(view)
        defer { window.contentView = nil }
        view.frameTick()
        view.withTerminal { $0.clearUpdateRange() }
        view.invalidated.removeAll()
        let timer = try #require(view.textBlinkTimer)
        timer.fire()
        view.frameTick()
        let band = rowBand(view, screenRow: 2)
        #expect(view.invalidated.contains { $0.minY <= band.bottom && $0.maxY >= band.top },
                "invalidated \(view.invalidated)")
    }

    // MARK: - (3) Metal draw data across the blink phase (A3)

#if canImport(MetalKit)
    // Incremental Metal draw data must equal a from-scratch rebuild of the
    // same state (`MetalRowCacheTests.Harness.freshFrame`), the v1.99.2 seam
    // for the fork's optimized-vs-ground-truth draw snapshot.
    private func glyphBytes(_ frame: MetalRowCacheTests.DrawnFrame, row: Int) -> [UInt8]? {
        row < frame.rows.count ? frame.rows[row] : nil
    }

    @Test(.enabled(if: MetalRowCacheTests.metalIsUsable, "needs Metal"))
    func metalDrawDataTracksBlinkHookPhase() async throws {
        let harness = try #require(MetalRowCacheTests.Harness(cols: 40, rows: 12))
        let view = harness.view
        view.feed(text: "plain neighbor\r\n" + blinkLine)
        let visible = try #require(await harness.frame())

        view.setTextBlinkVisibleForTesting(false)
        let optimized = try #require(await harness.frame())
        let truth = try #require(await harness.freshFrame())

        #expect(truth.rows != visible.rows, "control: hidden phase must change draw data")
        #expect(optimized.rows == truth.rows, "Metal draw data kept the stale blink phase")
    }

    @Test(.enabled(if: MetalRowCacheTests.metalIsUsable && !reduceMotion, "needs Metal; Reduce Motion disables the blink timer"))
    func metalDrawDataTracksBlinkTimerPhase() async throws {
        let harness = try #require(MetalRowCacheTests.Harness(cols: 40, rows: 12))
        let view = harness.view
        view.feed(text: "plain neighbor\r\n" + blinkLine)
        let window = hostForBlinking(view)
        defer { window.contentView = nil }
        let timer = try #require(view.textBlinkTimer)
        let visible = try #require(await harness.frame())

        timer.fire()
        #expect(view.textBlinkVisible == false)
        let optimized = try #require(await harness.frame())
        let truth = try #require(await harness.freshFrame())

        #expect(truth.rows != visible.rows, "control: hidden phase must change draw data")
        #expect(optimized.rows == truth.rows, "Metal draw data kept the stale blink phase (timer path)")
    }
#endif

    // MARK: - (4) Translucent themes x Metal x DECSCNM (A8)
    //
    // Contract (coordinator decision): `TerminalTheme.background` is a full
    // color including alpha, and applying a theme adopts that alpha — it does
    // not preserve a previously set `backgroundOpacity`. Assigning an
    // alpha-bearing `nativeBackgroundColor` is equivalent to `backgroundOpacity`,
    // so the layer ownership rules of that API must hold for themes too.

    private func layerColor(_ view: TerminalView) -> RGBA? {
        RGBA(view.layer?.backgroundColor)
    }

    /// Distinct RGB per theme so a stale color can never match by accident.
    private func theme(fg: (Int, Int, Int), bg: (Int, Int, Int), alpha: CGFloat) -> TerminalTheme {
        func c(_ v: (Int, Int, Int), _ a: CGFloat = 1) -> NSColor {
            NSColor(srgbRed: CGFloat(v.0) / 255, green: CGFloat(v.1) / 255, blue: CGFloat(v.2) / 255, alpha: a)
        }
        var t = TerminalTheme.swiftTermDark
        t.foreground = c(fg)
        t.background = c(bg, alpha)
        t.caret = c(fg)
        t.caretText = c(bg)
        return t
    }

    private var translucentDark: TerminalTheme { theme(fg: (220, 210, 190), bg: (20, 30, 50), alpha: 0.2) }
    private var translucentLight: TerminalTheme { theme(fg: (40, 20, 10), bg: (240, 230, 210), alpha: 0.4) }
    private var opaqueLight: TerminalTheme { theme(fg: (10, 60, 10), bg: (250, 250, 235), alpha: 1) }

    /// Installs both themes without applying the light one early, leaving the
    /// view on the dark theme.
    private func install(_ view: TerminalView, dark: TerminalTheme, light: TerminalTheme) {
        view.lightTheme = light      // not applied: resolved appearance is dark
        view.darkTheme = dark        // applied
        view.terminalAppearance = .dark
    }

    /// CG: each switch adopts the chosen theme's RGB and alpha on the model
    /// color and on the layer that paints the margins.
    @Test func cgTranslucentThemesApplyThemeAlphaAcrossSwitches() throws {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 120))
        let dark = translucentDark, light = translucentLight
        install(view, dark: dark, light: light)
        for (name, t) in [("dark", dark), ("light", light), ("dark again", dark)] {
            view.terminalAppearance = name.hasPrefix("dark") ? .dark : .light
            let want = RGBA(t.background)
            #expect(RGBA(view.nativeBackgroundColor) == want, "\(name): model \(RGBA(view.nativeBackgroundColor))")
            #expect(abs(view.backgroundOpacity - t.background.alphaComponent) < 0.01, "\(name): opacity \(view.backgroundOpacity)")
            #expect(layerColor(view) == want, "\(name): CG layer \(String(describing: layerColor(view)))")
        }
    }

    /// Control protecting the existing theme-alpha API: an opaque theme
    /// applied after `backgroundOpacity = 0.4` makes the view opaque again.
    @Test func cgOpaqueThemeAfterTranslucentOpacityRestoresOpacityOne() throws {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 120))
        view.backgroundOpacity = 0.4
        #expect(layerColor(view)?.a == 40, "control: opacity API")
        view.lightTheme = opaqueLight
        view.terminalAppearance = .light
        #expect(abs(view.backgroundOpacity - 1) < 0.01)
        #expect(layerColor(view) == RGBA(opaqueLight.background))
    }

    /// CG DECSCNM with translucent themes, including a theme switch while
    /// reversed: the swap follows the new theme, and reverse-off lands on the
    /// new theme's background with its alpha.
    @Test func cgReverseScreenAcrossTranslucentThemeSwitch() async throws {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 120))
        let dark = translucentDark, light = translucentLight
        install(view, dark: dark, light: light)

        view.feed(text: "\(esc)[?5h")
        await drainMainQueue()
        #expect(reverseColors(view))
        #expect(layerColor(view)?.rgb == RGBA(dark.foreground).rgb, "reversed layer: \(String(describing: layerColor(view)))")
        print("UPSTREAM119_CG_REVERSE_LAYER_ALPHA \(String(describing: layerColor(view)))")
        view.feed(text: "\(esc)[?5l")
        await drainMainQueue()
        #expect(layerColor(view) == RGBA(dark.background), "control: un-reverse restores theme bg + alpha")

        view.feed(text: "\(esc)[?5h")
        await drainMainQueue()
        view.terminalAppearance = .light
        #expect(RGBA(view.effectiveNativeBackgroundColor).rgb == RGBA(light.foreground).rgb)
        #expect(RGBA(view.effectiveNativeForegroundColor) == RGBA(light.background),
                "reversed fg after switch: \(RGBA(view.effectiveNativeForegroundColor))")
        #expect(layerColor(view)?.rgb == RGBA(light.foreground).rgb,
                "theme switch while reversed painted layer \(String(describing: layerColor(view)))")

        view.feed(text: "\(esc)[?5l")
        await drainMainQueue()
        #expect(layerColor(view) == RGBA(light.background), "after reverse off: \(String(describing: layerColor(view)))")
    }

#if canImport(MetalKit)
    /// Real Metal renderer enabled at the default opaque background, then a
    /// translucent theme applied: the Metal clear color carries the theme
    /// alpha, the host layer stays clear (no double composite), and the
    /// CAMetalLayer composites (`isOpaque == false`), exactly as assigning the
    /// same color through `nativeBackgroundColor`/`backgroundOpacity` would.
    /// An opaque background is also painted on the host layer, so nothing
    /// shows through before the Metal surface has a drawable (adjudication 7).
    @Test(.enabled(if: hasMetal, "needs a Metal device"))
    func metalTranslucentThemeAfterOpaqueEnable() throws {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 120))
        try view.setUseMetal(true)
        defer { try? view.setUseMetal(false) }
        let metalLayer = try #require(view.metalView?.layer)
        // Control: default opaque state under Metal.
        #expect(metalLayer.isOpaque == true)
        #expect(layerColor(view) == RGBA(view.effectiveNativeBackgroundColor))

        let dark = translucentDark, light = translucentLight
        install(view, dark: dark, light: light)
        for (name, t) in [("dark", dark), ("light", light)] {
            view.terminalAppearance = name == "dark" ? .dark : .light
            #expect(RGBA(view.effectiveNativeBackgroundColor) == RGBA(t.background),
                    "\(name): Metal clear color \(RGBA(view.effectiveNativeBackgroundColor))")
            #expect(layerColor(view)?.a == 0, "\(name): host layer under Metal \(String(describing: layerColor(view)))")
            #expect(metalLayer.isOpaque == false, "\(name): CAMetalLayer.isOpaque with theme alpha \(t.background.alphaComponent)")
        }

        // Control: an opaque theme makes the Metal layer opaque again.
        view.lightTheme = opaqueLight
        #expect(RGBA(view.effectiveNativeBackgroundColor) == RGBA(opaqueLight.background))
        #expect(metalLayer.isOpaque == true)
        #expect(layerColor(view) == RGBA(opaqueLight.background),
                "host layer under Metal after opaque theme \(String(describing: layerColor(view)))")
    }

    @Test(.enabled(if: hasMetal, "needs a Metal device"))
    func metalReverseScreenAcrossTranslucentThemeSwitch() async throws {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 120))
        try view.setUseMetal(true)
        defer { try? view.setUseMetal(false) }
        let dark = translucentDark, light = translucentLight
        install(view, dark: dark, light: light)

        view.feed(text: "\(esc)[?5h")
        await drainMainQueue()
        #expect(RGBA(view.effectiveNativeBackgroundColor).rgb == RGBA(dark.foreground).rgb)
        view.feed(text: "\(esc)[?5l")
        await drainMainQueue()
        #expect(RGBA(view.effectiveNativeBackgroundColor) == RGBA(dark.background), "control: un-reverse")

        view.feed(text: "\(esc)[?5h")
        await drainMainQueue()
        // Reversed, the effective background is the theme's opaque
        // foreground, so the host layer paints it.
        #expect(layerColor(view) == RGBA(view.effectiveNativeBackgroundColor),
                "host layer under Metal after theme install + DECSCNM: \(String(describing: layerColor(view)))")
        view.terminalAppearance = .light
        #expect(RGBA(view.effectiveNativeBackgroundColor).rgb == RGBA(light.foreground).rgb)
        #expect(RGBA(view.effectiveNativeForegroundColor) == RGBA(light.background))
        #expect(layerColor(view) == RGBA(view.effectiveNativeBackgroundColor),
                "host layer under Metal after reversed theme switch: \(String(describing: layerColor(view)))")
        view.feed(text: "\(esc)[?5l")
        await drainMainQueue()
        #expect(RGBA(view.effectiveNativeBackgroundColor) == RGBA(light.background),
                "Metal clear color after reverse off: \(RGBA(view.effectiveNativeBackgroundColor))")
        #expect(layerColor(view)?.a == 0, "translucent background under Metal must leave the host layer clear")
    }
#endif

    /// Default-color bold under DECSCNM: the custom bold color applies only
    /// when not reversed; reversed swaps the defaults; explicit ANSI is
    /// unaffected by either. Checked through the color map the renderers use
    /// (the frame render context) and through the rendered attributes.
    @Test func boldDefaultForegroundUnderReverseScreen() async throws {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 120))
        let custom = NSColor(srgbRed: 1, green: 0.2, blue: 0.6, alpha: 1)
        // Static colors: the dynamic system defaults resolve against the view's
        // effective appearance in the renderer but the process appearance in
        // RGBA(), so they disagree whenever the system is in dark mode.
        view.nativeForegroundColor = NSColor(srgbRed: 0.9, green: 0.85, blue: 0.8, alpha: 1)
        view.nativeBackgroundColor = NSColor(srgbRed: 0.1, green: 0.12, blue: 0.2, alpha: 1)
        view.nativeBoldForegroundColor = custom
        let fg = RGBA(view.nativeForegroundColor), bg = RGBA(view.nativeBackgroundColor)
        func rendered(_ color: Attribute.Color, isFg: Bool, isBold: Bool) -> RGBA {
            let (_, context) = frameSnapshot(view)
            return RGBA(SwiftTerm.mapColor(color: color, isFg: isFg, isBold: isBold, context: context))
        }
        let ansiBold = rendered(.ansi256(code: 1), isFg: true, isBold: true)
        // The renderer rebuilds captured sRGB colors, which can move a channel
        // by one 8-bit step; a missing swap moves it by far more.
        func same(_ a: RGBA, _ b: RGBA) -> Bool {
            abs(a.r - b.r) <= 1 && abs(a.g - b.g) <= 1 && abs(a.b - b.b) <= 1 && a.a == b.a
        }

        #expect(same(rendered(.defaultColor, isFg: true, isBold: true), RGBA(custom)))
        #expect(same(rendered(.defaultColor, isFg: true, isBold: false), fg))

        view.feed(text: "\(esc)[1mB\(esc)[0m \(esc)[1;31mR\(esc)[0m")
        let boldAttr = try #require(cachedFirstCell(view, row: 0)?.attributes[.foregroundColor] as? NSColor)
        #expect(same(RGBA(boldAttr), RGBA(custom)))

        view.feed(text: "\(esc)[?5h")
        await drainMainQueue()
        #expect(reverseColors(view))
        #expect(same(rendered(.defaultColor, isFg: true, isBold: true), bg),
                "bold default fg under reverse must be the swapped default, not the custom bold color")
        #expect(same(rendered(.defaultColor, isFg: true, isBold: false), bg),
                "reversed default fg \(rendered(.defaultColor, isFg: true, isBold: false)) vs bg \(bg); fg \(fg)")
        #expect(same(rendered(.defaultColor, isFg: false, isBold: false), fg),
                "reversed default bg \(rendered(.defaultColor, isFg: false, isBold: false)) vs fg \(fg)")
        #expect(same(rendered(.ansi256(code: 1), isFg: true, isBold: true), ansiBold))

        let reversedAttr = try #require(cachedFirstCell(view, row: 0)?.attributes[.foregroundColor] as? NSColor)
        #expect(same(RGBA(reversedAttr), bg), "cache served pre-reverse bold color")

        view.feed(text: "\(esc)[?5l")
        await drainMainQueue()
        #expect(same(rendered(.defaultColor, isFg: true, isBold: true), RGBA(custom)))
        #expect(same(rendered(.ansi256(code: 1), isFg: true, isBold: true), ansiBold))
        #expect(!same(ansiBold, RGBA(custom)))
    }
}
#endif
