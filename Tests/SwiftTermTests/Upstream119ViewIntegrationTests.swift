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
//  synchronously — and then observes what the renderers actually consume
//  (`cachedLineInfo`, CG pixels, CG invalidation rects, Metal draw data), never
//  a fresh `buildAttributedString` alone. A fresh build is used only as the
//  control proving the phase really is hidden.
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

    /// The first rendered segment of `row` as the renderers see it (through the
    /// line-info cache), with the attributes of its first cell.
    private func cachedFirstCell(_ view: TerminalView, row: Int)
        -> (text: String, attributes: [NSAttributedString.Key: Any])?
    {
        let buffer = view.terminal.displayBuffer
        let info = view.cachedLineInfo(row: row, line: buffer.lines[row], cols: view.terminal.cols)
        guard let segment = info.segments.first(where: { $0.column == 0 }),
              segment.attributedString.length > 0 else { return nil }
        return (segment.attributedString.string,
                segment.attributedString.attributes(at: 0, effectiveRange: nil))
    }

    /// Same as `cachedFirstCell` but bypassing the cache (the control).
    private func freshFirstCell(_ view: TerminalView, row: Int)
        -> (text: String, attributes: [NSAttributedString.Key: Any])?
    {
        let buffer = view.terminal.displayBuffer
        let info = view.buildAttributedString(row: row, line: buffer.lines[row], cols: view.terminal.cols)
        guard let segment = info.segments.first(where: { $0.column == 0 }),
              segment.attributedString.length > 0 else { return nil }
        return (segment.attributedString.string,
                segment.attributedString.attributes(at: 0, effectiveRange: nil))
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
        view.terminal.feed(text: blinkLine)
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

    /// Warm `cachedLineInfo` in the visible phase, toggle hidden with the hook:
    /// what the renderers read must be the hidden phase, and a neighboring
    /// non-blink row must keep its cache entry (no global cache reset).
    @Test func blinkHookToggleIsVisibleThroughCachedLineInfo() throws {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 120))
        view.terminal.feed(text: "plain neighbor\r\n" + blinkLine)
        let blinkRow = 1, neighborRow = 0

        let warm = try #require(cachedFirstCell(view, row: blinkRow))
        #expect(warm.text.first == "B")
        _ = cachedFirstCell(view, row: neighborRow)
        let neighborLine = view.terminal.displayBuffer.lines[neighborRow]
        let cacheGenerationBefore = view.lineInfoCacheGeneration
        let neighborInvalidationBefore = view.lineInfoInvalidationGeneration(for: neighborLine)

        view.setTextBlinkVisibleForTesting(false)
        #expect(view.textBlinkVisible == false)

        let hidden = try #require(cachedFirstCell(view, row: blinkRow))
        #expect(hidden.text.first == " ", "cachedLineInfo served stale blink phase: \(hidden.text.debugDescription)")
        #expect(hidden.attributes[.backgroundColor] != nil)
        #expect(hidden.attributes[.underlineStyle] == nil, "stale underline in hidden phase")
        #expect(hidden.attributes[.strikethroughStyle] == nil, "stale strikethrough in hidden phase")

        // The neighbor must stay cached: blink is a per-row invalidation.
        #expect(view.lineInfoCacheGeneration == cacheGenerationBefore)
        #expect(view.lineInfoCache[neighborRow] != nil)
        #expect(view.lineInfoInvalidationGeneration(for: neighborLine) == neighborInvalidationBefore)

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
        view.terminal.feed(text: "plain neighbor\r\n" + blinkLine)
        let window = hostForBlinking(view)
        defer { window.contentView = nil }
        let timer = try #require(view.textBlinkTimer, "blink timer must start for a hosted, active view")
        #expect(view.textBlinkVisible)

        let warm = try #require(cachedFirstCell(view, row: 1))
        #expect(warm.text.first == "B")
        _ = cachedFirstCell(view, row: 0)
        let cacheGenerationBefore = view.lineInfoCacheGeneration

        timer.fire()
        #expect(view.textBlinkVisible == false, "timer fire must hide")
        #expect(view.textBlinkTimer === timer, "phase must not be reset by the lifecycle")

        let hidden = try #require(cachedFirstCell(view, row: 1))
        #expect(hidden.text.first == " ", "cachedLineInfo served stale blink phase: \(hidden.text.debugDescription)")
        #expect(hidden.attributes[.underlineStyle] == nil, "stale underline in hidden phase")
        #expect(view.lineInfoCacheGeneration == cacheGenerationBefore)
        #expect(view.lineInfoCache[0] != nil, "non-blink neighbor must stay cached")
    }

    /// CG pixels: a view whose cache was warmed in the visible phase and then
    /// toggled hidden must draw exactly what a cold view in the hidden phase
    /// draws. Control: hidden and visible frames differ.
    @Test func blinkHiddenPhaseCGPixelsMatchColdRender() throws {
        func makeView() -> TerminalView {
            let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 120))
            view.terminal.feed(text: "plain neighbor\r\n" + blinkLine + "\(esc)[?25l")
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
        let terminal: Terminal = view.terminal
        for i in 0..<screenRow { terminal.feed(text: "pre \(i)\r\n") }
        terminal.feed(text: blinkLine + "\r\n")
        for i in 0..<(terminal.rows * 3) { terminal.feed(text: "line \(i)\r\n") }
        let window = hosted ? hostForBlinking(view) : nil
        view.updateDisplay()
        view.scrollTo(row: 0)
        view.updateDisplay()
        terminal.clearUpdateRange()
        view.invalidated.removeAll()
        return (view, window)
    }

    /// Control for the helper: the fork's own viewport-row invalidation
    /// (hover path) hits the band the blink test expects.
    @Test func scrolledBackViewportRowControlHitsBand() {
        let screenRow = 2
        let (view, _) = makeDeepScrolledBackBlinkView(screenRow: screenRow, hosted: false)
        let buffer = view.terminal.buffer
        #expect(buffer.yBase - buffer.yDisp >= view.terminal.rows)
        #expect(view.visibleBlinkRows() == [buffer.yDisp + screenRow])
        view.invalidateAppearanceRow(buffer.yDisp + screenRow)
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
        view.updateDisplay()
        #expect(view.textBlinkVisible == false, "setup: display tick must not reset the phase")

        let band = rowBand(view, screenRow: screenRow)
        let repainted = view.invalidated.contains { $0.minY <= band.bottom && $0.maxY >= band.top }
        #expect(repainted, "blink toggle while scrolled back invalidated \(view.invalidated); row band [\(band.bottom), \(band.top)]")

        // What the next draw would read for that row must be the hidden phase.
        let hidden = try #require(cachedFirstCell(view, row: buffer.yDisp + screenRow))
        #expect(hidden.text.first == " ", "scrolled-back blink row cached in stale phase")
    }

    /// Test-hook path (`setTextBlinkVisibleForTesting` duplicates the
    /// production row loop instead of calling `invalidateTextBlinkRows`).
    /// Unhosted, so the next display tick's lifecycle resets the phase to
    /// visible — that reset re-invalidates the same rows, so the band must
    /// still be repainted.
    @Test func blinkHookWhileDeepScrolledBackInvalidatesViewportRow() {
        let screenRow = 2
        let (view, _) = makeDeepScrolledBackBlinkView(screenRow: screenRow, hosted: false)
        view.setTextBlinkVisibleForTesting(false)
        view.updateDisplay()
        let band = rowBand(view, screenRow: screenRow)
        let repainted = view.invalidated.contains { $0.minY <= band.bottom && $0.maxY >= band.top }
        #expect(repainted, "blink hook while scrolled back invalidated \(view.invalidated); row band [\(band.bottom), \(band.top)]")
    }

    /// Control: pinned to the bottom, the same timer path does hit the row,
    /// proving the scrolled-back failure is the live-space/viewport mismatch.
    @Test(.enabled(if: !reduceMotion, "Reduce Motion disables the blink timer"))
    func blinkTimerPinnedInvalidatesRow() throws {
        let view = BlinkInvalidationCapturingView(frame: CGRect(x: 0, y: 0, width: 640, height: 320))
        view.terminal.feed(text: "a\r\nb\r\n" + blinkLine + "\r\n")
        let window = hostForBlinking(view)
        defer { window.contentView = nil }
        view.updateDisplay()
        view.terminal.clearUpdateRange()
        view.invalidated.removeAll()
        let timer = try #require(view.textBlinkTimer)
        timer.fire()
        view.updateDisplay()
        let band = rowBand(view, screenRow: 2)
        #expect(view.invalidated.contains { $0.minY <= band.bottom && $0.maxY >= band.top },
                "invalidated \(view.invalidated)")
    }

    // MARK: - (3) Metal draw data across the blink phase (A3)

#if DEBUG && canImport(MetalKit)
    private func makeMetalHarness() -> (TerminalView, MetalTerminalRenderer) {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        view.resize(cols: 40, rows: 12)
        view.frame.size = CGSize(width: view.cellDimension.width * 40,
                                 height: view.cellDimension.height * 12)
        let renderer = MetalTerminalRenderer(debugTerminalView: view)
        view.metalRenderer = renderer
        return (view, renderer)
    }

    private func transferTerminalDirtyRange(to view: TerminalView) {
        let terminal = view.terminal!
        guard let (rowStart, rowEnd) = terminal.getUpdateRange() else {
            view.setMetalDirtyRange(nil)
            return
        }
        let buffer = terminal.displayBuffer
        let maxRow = buffer.lines.count - 1
        let start = max(0, min(buffer.yDisp + rowStart, maxRow))
        let end = max(0, min(buffer.yDisp + rowEnd, maxRow))
        view.setMetalDirtyRange(start <= end ? start...end : nil)
        terminal.clearUpdateRange()
    }

    /// Ground truth for the current phase: drop both the view line-info cache
    /// and the Metal row cache, then build.
    private func groundTruth(_ view: TerminalView, _ renderer: MetalTerminalRenderer) -> MetalRendererDebugDrawSnapshot {
        view.resetLineInfoCache()
        return renderer.debugBuildSnapshot(scale: 1, forceFullRebuild: true)
    }

    private func glyphCount(_ snapshot: MetalRendererDebugDrawSnapshot, row: Int) -> Int {
        guard let r = snapshot.rows.first(where: { $0.row == row }) else { return -1 }
        return r.glyphCellsGray.count + r.glyphCellsColor.count
    }

    @Test func metalDrawDataTracksBlinkHookPhase() throws {
        let (view, renderer) = makeMetalHarness()
        view.terminal.feed(text: "plain neighbor\r\n" + blinkLine)
        transferTerminalDirtyRange(to: view)
        let visible = renderer.debugBuildSnapshot(scale: 1)

        view.setTextBlinkVisibleForTesting(false)
        transferTerminalDirtyRange(to: view)
        renderer.debugResetMetrics()
        let optimized = renderer.debugBuildSnapshot(scale: 1)
        let metrics = renderer.debugMetricsSnapshot()
        let truth = groundTruth(view, renderer)

        print("UPSTREAM119_METAL_BLINK_HOOK rowsRebuilt=\(metrics.rowsRebuilt) " +
              "glyphs visible=\(glyphCount(visible, row: 1)) optimized=\(glyphCount(optimized, row: 1)) " +
              "truth=\(glyphCount(truth, row: 1))")
        #expect(glyphCount(truth, row: 1) < glyphCount(visible, row: 1), "control: hidden phase must drop glyphs")
        #expect(glyphCount(truth, row: 0) == glyphCount(visible, row: 0), "control: neighbor unaffected")
        #expect(optimized == truth, "Metal draw data kept the stale blink phase")
    }

    @Test(.enabled(if: !reduceMotion, "Reduce Motion disables the blink timer"))
    func metalDrawDataTracksBlinkTimerPhase() throws {
        let (view, renderer) = makeMetalHarness()
        view.terminal.feed(text: "plain neighbor\r\n" + blinkLine)
        let window = hostForBlinking(view)
        defer { window.contentView = nil }
        let timer = try #require(view.textBlinkTimer)
        transferTerminalDirtyRange(to: view)
        let visible = renderer.debugBuildSnapshot(scale: 1)

        timer.fire()
        #expect(view.textBlinkVisible == false)
        transferTerminalDirtyRange(to: view)
        let optimized = renderer.debugBuildSnapshot(scale: 1)
        let truth = groundTruth(view, renderer)

        #expect(glyphCount(truth, row: 1) < glyphCount(visible, row: 1), "control: hidden phase must drop glyphs")
        #expect(optimized == truth, "Metal draw data kept the stale blink phase (timer path)")
    }
#endif

    // MARK: - (4) Appearance x backgroundOpacity x DECSCNM (A8)

    private func layerColor(_ view: TerminalView) -> RGBA? {
        RGBA(view.layer?.backgroundColor)
    }

    /// CG: switching appearance must keep the host's 0.4 background opacity
    /// on both the model color and the layer that paints the margins.
    @Test func cgAppearanceSwitchPreservesBackgroundOpacity() throws {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 120))
        view.backgroundOpacity = 0.4
        // Control: the opacity API itself works.
        #expect(abs(view.backgroundOpacity - 0.4) < 0.01)
        #expect(layerColor(view)?.a == 40)

        view.terminalAppearance = .light
        let light = RGBA(view.lightTheme.background)
        #expect(RGBA(view.nativeBackgroundColor).rgb == light.rgb)
        #expect(abs(view.backgroundOpacity - 0.4) < 0.01, "backgroundOpacity after light switch: \(view.backgroundOpacity)")
        #expect(layerColor(view)?.rgb == light.rgb)
        #expect(layerColor(view)?.a == 40, "CG layer after light switch: \(String(describing: layerColor(view)))")

        view.terminalAppearance = .dark
        #expect(abs(view.backgroundOpacity - 0.4) < 0.01, "backgroundOpacity after dark switch: \(view.backgroundOpacity)")
        #expect(layerColor(view)?.a == 40, "CG layer after dark switch: \(String(describing: layerColor(view)))")
    }

    /// CG DECSCNM on/off at 0.4 opacity, then a theme switch while reversed.
    @Test func cgReverseScreenAcrossThemeSwitch() throws {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 120))
        view.backgroundOpacity = 0.4
        let darkFg = RGBA(view.nativeForegroundColor)
        let darkBg = RGBA(view.nativeBackgroundColor)

        view.terminal.feed(text: "\(esc)[?5h")
        #expect(view.terminal.reverseColors)
        #expect(layerColor(view)?.rgb == darkFg.rgb, "reversed layer: \(String(describing: layerColor(view)))")
        print("UPSTREAM119_CG_REVERSE_LAYER_ALPHA \(String(describing: layerColor(view)))")

        view.terminal.feed(text: "\(esc)[?5l")
        #expect(layerColor(view)?.rgb == darkBg.rgb)
        #expect(layerColor(view)?.a == 40, "control: un-reverse restores opacity")

        view.terminal.feed(text: "\(esc)[?5h")
        view.terminalAppearance = .light
        let light = view.lightTheme
        #expect(RGBA(view.effectiveNativeBackgroundColor).rgb == RGBA(light.foreground).rgb)
        #expect(RGBA(view.effectiveNativeForegroundColor).rgb == RGBA(light.background).rgb)
        #expect(layerColor(view)?.rgb == RGBA(light.foreground).rgb,
                "theme switch while reversed painted layer \(String(describing: layerColor(view)))")

        view.terminal.feed(text: "\(esc)[?5l")
        #expect(layerColor(view)?.rgb == RGBA(light.background).rgb)
        #expect(layerColor(view)?.a == 40, "after reverse off under light theme: \(String(describing: layerColor(view)))")
    }

#if canImport(MetalKit)
    /// Metal owns the background through its clear color; the host layer must
    /// stay clear (else a translucent background composites twice) across a
    /// theme switch, and the clear color must keep the 0.4 opacity.
    @Test(.enabled(if: hasMetal, "needs a Metal device"))
    func metalAppearanceSwitchKeepsLayerClearAndOpacity() throws {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 120))
        try view.setUseMetal(true)
        defer { try? view.setUseMetal(false) }
        view.backgroundOpacity = 0.4
        let metalLayer = try #require(view.metalView?.layer)
        // Control
        #expect(layerColor(view)?.a == 0)
        #expect(metalLayer.isOpaque == false)
        #expect(RGBA(view.effectiveNativeBackgroundColor).a == 40)

        view.terminalAppearance = .light
        #expect(layerColor(view)?.a == 0, "host layer under Metal after light switch: \(String(describing: layerColor(view)))")
        #expect(RGBA(view.effectiveNativeBackgroundColor).a == 40,
                "Metal clear color after light switch: \(RGBA(view.effectiveNativeBackgroundColor))")
        #expect(RGBA(view.effectiveNativeBackgroundColor).rgb == RGBA(view.lightTheme.background).rgb)
        #expect(metalLayer.isOpaque == false)
    }

    @Test(.enabled(if: hasMetal, "needs a Metal device"))
    func metalReverseScreenAcrossThemeSwitch() throws {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 120))
        try view.setUseMetal(true)
        defer { try? view.setUseMetal(false) }
        view.backgroundOpacity = 0.4
        let darkFg = RGBA(view.nativeForegroundColor)

        view.terminal.feed(text: "\(esc)[?5h")
        #expect(layerColor(view)?.a == 0, "control: DECSCNM keeps Metal host layer clear")
        #expect(RGBA(view.effectiveNativeBackgroundColor).rgb == darkFg.rgb)
        view.terminal.feed(text: "\(esc)[?5l")
        #expect(layerColor(view)?.a == 0)

        view.terminal.feed(text: "\(esc)[?5h")
        view.terminalAppearance = .light
        #expect(RGBA(view.effectiveNativeBackgroundColor).rgb == RGBA(view.lightTheme.foreground).rgb)
        #expect(layerColor(view)?.a == 0, "host layer under Metal after reversed theme switch: \(String(describing: layerColor(view)))")
        view.terminal.feed(text: "\(esc)[?5l")
        #expect(layerColor(view)?.a == 0)
        #expect(RGBA(view.effectiveNativeBackgroundColor).a == 40,
                "Metal clear color after reverse off: \(RGBA(view.effectiveNativeBackgroundColor))")
    }
#endif

    /// Default-color bold under DECSCNM: the custom bold color applies only
    /// when not reversed; reversed swaps the defaults; explicit ANSI is
    /// unaffected by either. Checked through mapColor and through the cache.
    @Test func boldDefaultForegroundUnderReverseScreen() throws {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 120))
        let custom = NSColor(srgbRed: 1, green: 0.2, blue: 0.6, alpha: 1)
        view.nativeBoldForegroundColor = custom
        let fg = RGBA(view.nativeForegroundColor), bg = RGBA(view.nativeBackgroundColor)
        let ansiBold = RGBA(view.mapColor(color: .ansi256(code: 1), isFg: true, isBold: true))

        #expect(RGBA(view.mapColor(color: .defaultColor, isFg: true, isBold: true)) == RGBA(custom))
        #expect(RGBA(view.mapColor(color: .defaultColor, isFg: true, isBold: false)) == fg)

        view.terminal.feed(text: "\(esc)[1mB\(esc)[0m \(esc)[1;31mR\(esc)[0m")
        let boldAttr = try #require(cachedFirstCell(view, row: 0)?.attributes[.foregroundColor] as? NSColor)
        #expect(RGBA(boldAttr).rgb == RGBA(custom).rgb)

        view.terminal.feed(text: "\(esc)[?5h")
        #expect(view.terminal.reverseColors)
        #expect(RGBA(view.mapColor(color: .defaultColor, isFg: true, isBold: true)) == bg,
                "bold default fg under reverse must be the swapped default, not the custom bold color")
        #expect(RGBA(view.mapColor(color: .defaultColor, isFg: true, isBold: false)) == bg)
        #expect(RGBA(view.mapColor(color: .defaultColor, isFg: false, isBold: false)) == fg)
        #expect(RGBA(view.mapColor(color: .ansi256(code: 1), isFg: true, isBold: true)) == ansiBold)

        let reversedAttr = try #require(cachedFirstCell(view, row: 0)?.attributes[.foregroundColor] as? NSColor)
        #expect(RGBA(reversedAttr).rgb == bg.rgb, "cache served pre-reverse bold color")

        view.terminal.feed(text: "\(esc)[?5l")
        #expect(RGBA(view.mapColor(color: .defaultColor, isFg: true, isBold: true)) == RGBA(custom))
        #expect(RGBA(view.mapColor(color: .ansi256(code: 1), isFg: true, isBold: true)) == ansiBold)
        #expect(ansiBold.rgb != RGBA(custom).rgb)
    }
}
#endif
