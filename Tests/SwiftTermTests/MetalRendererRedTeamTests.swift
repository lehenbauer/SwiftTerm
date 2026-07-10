#if os(macOS)
import AppKit
import CoreText
import Foundation
import Testing

@testable import SwiftTerm

@MainActor
@Suite(.serialized)
final class MetalRendererRedTeamTests {
    @Test func blockAntialiasToggleWithoutScrollMatchesFullRebuild() throws {
        let (view, renderer) = makeHarness()
        let blockLine = "\u{2588}\u{2580}\u{2584}\u{258c}\u{2590} cached block glyphs\r\n"
        view.terminal.feed(text: String(repeating: blockLine, count: 40))
        transferTerminalDirtyRange(to: view)
        _ = renderer.debugBuildSnapshot(scale: 1)

        renderer.debugResetMetrics()
        view.antiAliasCustomBlockGlyphs.toggle()
        transferTerminalDirtyRange(to: view)

        let optimized = renderer.debugBuildSnapshot(scale: 1)
        let metrics = renderer.debugMetricsSnapshot()
        let forced = renderer.debugBuildSnapshot(scale: 1, forceFullRebuild: true)
        let snapshotsEqual = optimized == forced

        print(
            "REDTEAM_BLOCK_AA_NO_SCROLL snapshotsEqual=\(snapshotsEqual) " +
            "rowsRemapped=\(metrics.rowsRemapped) rowsRebuilt=\(metrics.rowsRebuilt) " +
            "rowsCached=\(metrics.rowsCached) dirtyRows=\(metrics.dirtyRowsRequested)"
        )
        #expect(metrics.rowsRemapped == 0)
        #expect(metrics.rowsRebuilt == 12)
        #expect(snapshotsEqual)
    }

    @Test func scrollCoalescedWithBlockAntialiasToggleMatchesFullRebuild() throws {
        let (view, renderer) = makeHarness()

        let blockLine = "\u{2588}\u{2580}\u{2584}\u{258c}\u{2590} cached block glyphs\r\n"
        view.terminal.feed(text: String(repeating: blockLine, count: 40))
        transferTerminalDirtyRange(to: view)
        _ = renderer.debugBuildSnapshot(scale: 1)

        renderer.debugResetMetrics()
        view.terminal.feed(text: "scroll one row\r\n")
        let lineInfoGenerationBefore = view.lineInfoCacheGeneration
        view.antiAliasCustomBlockGlyphs.toggle()
        let lineInfoGenerationAfter = view.lineInfoCacheGeneration
        transferTerminalDirtyRange(to: view)

        let optimized = renderer.debugBuildSnapshot(scale: 1)
        let metrics = renderer.debugMetricsSnapshot()
        let forced = renderer.debugBuildSnapshot(scale: 1, forceFullRebuild: true)
        let snapshotsEqual = optimized == forced

        print(
            "REDTEAM_BLOCK_AA_SCROLL snapshotsEqual=\(snapshotsEqual) " +
            "rowsRemapped=\(metrics.rowsRemapped) rowsRebuilt=\(metrics.rowsRebuilt) " +
            "rowsCached=\(metrics.rowsCached) dirtyRows=\(metrics.dirtyRowsRequested) " +
            "lineInfoGeneration=\(lineInfoGenerationBefore)->\(lineInfoGenerationAfter)"
        )
        #expect(metrics.rowsRemapped > 0)
        #expect(metrics.dirtyRowsRequested == 12)
        #expect(lineInfoGenerationAfter == lineInfoGenerationBefore)
        #expect(snapshotsEqual)
    }

    @Test func scrollCoalescedWithCustomBlockToggleMatchesFullRebuild() throws {
        let (view, renderer) = makeHarness()

        let blockLine = "\u{2588}\u{2580}\u{2584}\u{258c}\u{2590} cached block glyphs\r\n"
        view.terminal.feed(text: String(repeating: blockLine, count: 40))
        transferTerminalDirtyRange(to: view)
        _ = renderer.debugBuildSnapshot(scale: 1)

        renderer.debugResetMetrics()
        view.terminal.feed(text: "scroll one row\r\n")
        let fullRefreshGenerationBefore = view.terminal.fullRefreshGeneration
        view.customBlockGlyphs.toggle()
        let fullRefreshGenerationAfter = view.terminal.fullRefreshGeneration
        transferTerminalDirtyRange(to: view)

        let optimized = renderer.debugBuildSnapshot(scale: 1)
        let metrics = renderer.debugMetricsSnapshot()
        let forced = renderer.debugBuildSnapshot(scale: 1, forceFullRebuild: true)
        let snapshotsEqual = optimized == forced

        print(
            "REDTEAM_CUSTOM_BLOCK_SCROLL snapshotsEqual=\(snapshotsEqual) " +
            "rowsRemapped=\(metrics.rowsRemapped) rowsRebuilt=\(metrics.rowsRebuilt) " +
            "rowsCached=\(metrics.rowsCached) dirtyRows=\(metrics.dirtyRowsRequested) " +
            "fullRefreshGeneration=\(fullRefreshGenerationBefore)->\(fullRefreshGenerationAfter)"
        )
        #expect(metrics.rowsRemapped > 0)
        #expect(metrics.rowsRebuilt == 12)
        #expect(metrics.dirtyRowsRequested == 12)
        #expect(fullRefreshGenerationAfter == fullRefreshGenerationBefore + 1)
        #expect(snapshotsEqual)
    }

    @Test func scrollCoalescedWithBrightColorToggleMatchesFullRebuild() throws {
        let (view, renderer) = makeHarness()

        let brightLine = "\u{1b}[91mbright cached text\u{1b}[0m\r\n"
        view.terminal.feed(text: String(repeating: brightLine, count: 40))
        transferTerminalDirtyRange(to: view)
        _ = renderer.debugBuildSnapshot(scale: 1)

        renderer.debugResetMetrics()
        view.terminal.feed(text: "scroll one row\r\n")
        let fullRefreshGenerationBefore = view.terminal.fullRefreshGeneration
        view.useBrightColors.toggle()
        let fullRefreshGenerationAfter = view.terminal.fullRefreshGeneration
        transferTerminalDirtyRange(to: view)

        let optimized = renderer.debugBuildSnapshot(scale: 1)
        let metrics = renderer.debugMetricsSnapshot()
        let forced = renderer.debugBuildSnapshot(scale: 1, forceFullRebuild: true)
        let snapshotsEqual = optimized == forced

        print(
            "REDTEAM_BRIGHT_COLOR_SCROLL snapshotsEqual=\(snapshotsEqual) " +
            "rowsRemapped=\(metrics.rowsRemapped) rowsRebuilt=\(metrics.rowsRebuilt) " +
            "rowsCached=\(metrics.rowsCached) dirtyRows=\(metrics.dirtyRowsRequested) " +
            "fullRefreshGeneration=\(fullRefreshGenerationBefore)->\(fullRefreshGenerationAfter)"
        )
        #expect(metrics.rowsRemapped > 0)
        #expect(metrics.rowsRebuilt == 12)
        #expect(metrics.dirtyRowsRequested == 12)
        #expect(fullRefreshGenerationAfter == fullRefreshGenerationBefore + 1)
        #expect(snapshotsEqual)
    }

    @Test func fullRefreshInvalidatesRowsWithoutDirtyTransfer() throws {
        let (view, renderer) = makeHarness()
        let blockLine = "\u{2588}\u{2580}\u{2584}\u{258c}\u{2590} cached block glyphs\r\n"
        view.terminal.feed(text: String(repeating: blockLine, count: 40))
        transferTerminalDirtyRange(to: view)
        _ = renderer.debugBuildSnapshot(scale: 1)

        renderer.debugResetMetrics()
        view.antiAliasCustomBlockGlyphs.toggle()

        let optimized = renderer.debugBuildSnapshot(scale: 1)
        let metrics = renderer.debugMetricsSnapshot()
        let forced = renderer.debugBuildSnapshot(scale: 1, forceFullRebuild: true)

        print(
            "REDTEAM_FULL_REFRESH_NO_DIRTY snapshotsEqual=\(optimized == forced) " +
            "rowsRebuilt=\(metrics.rowsRebuilt) dirtyRows=\(metrics.dirtyRowsRequested) " +
            "fullRefreshInvalidations=\(metrics.fullRefreshInvalidations)"
        )
        #expect(metrics.rowsRebuilt == 12)
        #expect(metrics.dirtyRowsRequested == 0)
        #expect(metrics.fullRefreshInvalidations == 1)
        #expect(optimized == forced)
    }

    @Test func fontSmoothingInvalidatesRasterizedGlyphRows() throws {
        let (view, renderer) = makeHarness()
        view.terminal.feed(text: String(repeating: "cached glyph text\r\n", count: 40))
        transferTerminalDirtyRange(to: view)
        _ = renderer.debugBuildSnapshot(scale: 1)

        renderer.debugResetMetrics()
        view.fontSmoothing.toggle()
        renderer.debugBuildOnly(scale: 1)
        let metrics = renderer.debugMetricsSnapshot()

        print(
            "REDTEAM_FONT_SMOOTHING rowsRebuilt=\(metrics.rowsRebuilt) " +
            "glyphMisses=\(metrics.glyphCacheMisses) " +
            "fullRefreshInvalidations=\(metrics.fullRefreshInvalidations)"
        )
        #expect(metrics.rowsRebuilt == 12)
        #expect(metrics.glyphCacheMisses > 0)
        #expect(metrics.fullRefreshInvalidations == 1)
    }

    @Test func retainedFontTableIsBoundedAcrossFontChanges() throws {
        let (view, renderer) = makeHarness()
        view.terminal.feed(text: "font cache probe\r\n")
        transferTerminalDirtyRange(to: view)
        _ = renderer.debugBuildSnapshot(scale: 1)
        let initialCount = renderer.debugMetricsSnapshot().retainedFontCount
        var maximumCount = initialCount

        for pointSize in 8..<40 {
            view.font = NSFont.monospacedSystemFont(ofSize: CGFloat(pointSize), weight: .regular)
            view.resize(cols: 40, rows: 12)
            view.frame.size = CGSize(width: view.cellDimension.width * 40,
                                     height: view.cellDimension.height * 12)
            _ = renderer.debugBuildSnapshot(scale: 1)
            maximumCount = max(maximumCount, renderer.debugMetricsSnapshot().retainedFontCount)
        }

        let finalCount = renderer.debugMetricsSnapshot().retainedFontCount
        print(
            "REDTEAM_RETAINED_FONTS initial=\(initialCount) final=\(finalCount) " +
            "maximum=\(maximumCount) changes=32 growth=\(finalCount - initialCount)"
        )
        #expect(finalCount <= initialCount + 1)
        #expect(maximumCount <= initialCount + 1)
    }

    @Test func circularScrollbackRotationMatchesFullRebuild() throws {
        let (view, renderer) = makeHarness(scrollback: 20)
        for line in 0..<100 {
            view.terminal.feed(text: "prefill \(line)\r\n")
        }
        transferTerminalDirtyRange(to: view)
        _ = renderer.debugBuildSnapshot(scale: 1)
        let initialYDisp = view.terminal.displayBuffer.yDisp
        var mismatches = 0

        for line in 0..<30 {
            view.terminal.feed(text: "rotate \(line)\r\n")
            transferTerminalDirtyRange(to: view)
            let optimized = renderer.debugBuildSnapshot(scale: 1)
            let forced = renderer.debugBuildSnapshot(scale: 1, forceFullRebuild: true)
            if optimized != forced {
                mismatches += 1
            }
        }

        let finalYDisp = view.terminal.displayBuffer.yDisp
        print(
            "REDTEAM_CIRCULAR_ROTATION frames=30 mismatches=\(mismatches) " +
            "yDisp=\(initialYDisp)->\(finalYDisp)"
        )
        #expect(finalYDisp == initialYDisp)
        #expect(mismatches == 0)
    }

    private func makeHarness(scrollback: Int = 200) -> (TerminalView, MetalTerminalRenderer) {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        view.resize(cols: 40, rows: 12)
        view.terminal.changeScrollback(scrollback)
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
}
#endif
