#if os(macOS)
import AppKit
import Foundation
import Testing

@testable import SwiftTerm

@MainActor
@Suite(.serialized)
final class MetalRendererRedTeamRound2Tests {
    @Test func fallbackFontRetentionStaysBoundedAcrossShaperChurn() throws {
        let (view, renderer) = makeHarness(scrollback: 3_000)
        view.terminal.feed(text: "warm fallback fonts 界🙂\r\n")
        transferTerminalDirtyRange(to: view)
        _ = renderer.debugBuildSnapshot(scale: 1)
        let initialCount = renderer.debugMetricsSnapshot().retainedFontCount
        var maximumCount = initialCount

        for frame in 0..<2_200 {
            view.terminal.feed(text: "unique shaper key \(frame) 界🙂\r\n")
            transferTerminalDirtyRange(to: view)
            renderer.debugBuildOnly(scale: 1)
            maximumCount = max(maximumCount, renderer.debugMetricsSnapshot().retainedFontCount)
        }

        let finalCount = renderer.debugMetricsSnapshot().retainedFontCount
        print(
            "REDTEAM2_SHAPER_CHURN frames=2200 retainedFonts=\(initialCount)->\(finalCount) " +
            "maximum=\(maximumCount)"
        )
        #expect(finalCount <= initialCount + 2)
        #expect(maximumCount <= initialCount + 2)
    }

    @Test func refreshStampBumpedAfterDirtyCaptureStillForcesFullRebuild() throws {
        let (view, renderer) = makeHarness()
        let blockLine = "\u{2588}\u{2580}\u{2584}\u{258c}\u{2590} cached block glyphs\r\n"
        view.terminal.feed(text: String(repeating: blockLine, count: 40))
        transferTerminalDirtyRange(to: view)
        _ = renderer.debugBuildSnapshot(scale: 1)

        renderer.debugResetMetrics()
        view.terminal.feed(text: "scroll one row\r\n")
        transferTerminalDirtyRange(to: view)
        let capturedGeneration = view.metalDirtyRangeFullRefreshGeneration
        view.antiAliasCustomBlockGlyphs.toggle()
        let currentGeneration = view.terminal.fullRefreshGeneration

        let optimized = renderer.debugBuildSnapshot(scale: 1)
        let metrics = renderer.debugMetricsSnapshot()
        let forced = renderer.debugBuildSnapshot(scale: 1, forceFullRebuild: true)
        let snapshotsEqual = optimized == forced

        print(
            "REDTEAM2_LATE_STAMP snapshotsEqual=\(snapshotsEqual) " +
            "capturedGeneration=\(String(describing: capturedGeneration)) " +
            "currentGeneration=\(currentGeneration) rowsRebuilt=\(metrics.rowsRebuilt) " +
            "fullRefreshInvalidations=\(metrics.fullRefreshInvalidations)"
        )
        #expect(capturedGeneration != currentGeneration)
        #expect(metrics.rowsRebuilt == 12)
        #expect(metrics.fullRefreshInvalidations == 1)
        #expect(snapshotsEqual)
    }

    @Test func resetFontSizeUsesCoordinatedMetalCacheReset() throws {
        let (view, renderer) = makeHarness()
        view.font = NSFont.monospacedSystemFont(ofSize: 24, weight: .regular)
        view.resize(cols: 40, rows: 12)
        view.frame.size = CGSize(width: view.cellDimension.width * 40,
                                 height: view.cellDimension.height * 12)
        view.terminal.feed(text: "font reset bypass probe\r\n")
        transferTerminalDirtyRange(to: view)
        let beforeSnapshot = renderer.debugBuildSnapshot(scale: 1)

        let beforeFontSize = view.font.pointSize
        let beforeCellDimension = view.cellDimension!
        let beforeCachedFontSizes = cachedLineFontSizes(in: view)
        let beforeCaches = renderer.debugMetricsSnapshot()
        view.resetFontSize()
        let afterFontSize = view.font.pointSize
        let afterCellDimension = view.cellDimension!
        let clearedCaches = renderer.debugMetricsSnapshot()
        let clearedLineInfoCount = view.lineInfoCache.count
        let afterSnapshot = renderer.debugBuildSnapshot(scale: 1)
        let afterCachedFontSizes = cachedLineFontSizes(in: view)
        let afterCaches = renderer.debugMetricsSnapshot()
        let snapshotsEqual = beforeSnapshot == afterSnapshot
        let rowSnapshotsEqual = beforeSnapshot.rows == afterSnapshot.rows

        print(
            "REDTEAM2_RESET_FONT_SIZE fontSize=\(beforeFontSize)->\(afterFontSize) " +
            "cellWidth=\(beforeCellDimension.width)->\(afterCellDimension.width) " +
            "cellHeight=\(beforeCellDimension.height)->\(afterCellDimension.height) " +
            "retainedFonts=\(beforeCaches.retainedFontCount)->\(clearedCaches.retainedFontCount)->\(afterCaches.retainedFontCount) " +
            "rowCache=\(beforeCaches.rowCacheEntryCount)->\(clearedCaches.rowCacheEntryCount)->\(afterCaches.rowCacheEntryCount) " +
            "glyphCache=\(beforeCaches.glyphCacheEntryCount)->\(clearedCaches.glyphCacheEntryCount)->\(afterCaches.glyphCacheEntryCount) " +
            "cachedFontSizes=\(beforeCachedFontSizes)->\(afterCachedFontSizes) " +
            "snapshotsEqual=\(snapshotsEqual) rowSnapshotsEqual=\(rowSnapshotsEqual)"
        )
        #expect(beforeCaches.retainedFontCount > 0)
        #expect(beforeCaches.rowCacheEntryCount > 0)
        #expect(beforeCaches.glyphCacheEntryCount > 0)
        #expect(beforeCaches.scaledFontCacheEntryCount > 0)
        #expect(beforeCaches.shaperCacheEntryCount > 0)
        #expect(clearedCaches.retainedFontCount == 0)
        #expect(clearedCaches.rowCacheEntryCount == 0)
        #expect(clearedCaches.glyphCacheEntryCount == 0)
        #expect(clearedCaches.scaledFontCacheEntryCount == 0)
        #expect(clearedCaches.shaperCacheEntryCount == 0)
        #expect(clearedCaches.customGlyphCacheEntryCount == 0)
        #expect(clearedLineInfoCount == 0)
        #expect(afterFontSize != beforeFontSize)
        #expect(afterCellDimension != beforeCellDimension)
        #expect(afterCachedFontSizes.contains(afterFontSize))
        #expect(!snapshotsEqual)
        #expect(!rowSnapshotsEqual)
    }

    @Test func scrollCoalescedWithHoverLinkInvalidationMatchesFullRebuild() throws {
        let (view, renderer) = makeHarness()
        view.linkHighlightMode = .hover
        let linkLine = "https://example.com cached link\r\n"
        view.terminal.feed(text: String(repeating: linkLine, count: 40))
        transferTerminalDirtyRange(to: view)
        _ = renderer.debugBuildSnapshot(scale: 1)

        renderer.debugResetMetrics()
        view.terminal.feed(text: "scroll one row\r\n")

        let buffer = view.terminal.displayBuffer
        let targetRow = buffer.yDisp + 5
        let match = try #require(
            view.terminal.linkMatch(
                at: .buffer(Position(col: 5, row: targetRow)),
                mode: .explicitAndImplicit
            )
        )
        let fullRefreshGenerationBefore = view.terminal.fullRefreshGeneration
        let lineInfoGenerationBefore = view.lineInfoCacheGeneration
        view.linkHighlightRange = match.rowRanges
        view.invalidateLinkHighlight(oldRange: nil, newRange: match.rowRanges)
        let fullRefreshGenerationAfter = view.terminal.fullRefreshGeneration
        let lineInfoGenerationAfter = view.lineInfoCacheGeneration
        transferTerminalDirtyRange(to: view)

        let optimized = renderer.debugBuildSnapshot(scale: 1)
        let metrics = renderer.debugMetricsSnapshot()
        let forced = renderer.debugBuildSnapshot(scale: 1, forceFullRebuild: true)
        let snapshotsEqual = optimized == forced

        print(
            "REDTEAM2_HOVER_LINK_SCROLL snapshotsEqual=\(snapshotsEqual) " +
            "rowsRemapped=\(metrics.rowsRemapped) rowsRebuilt=\(metrics.rowsRebuilt) " +
            "rowsCached=\(metrics.rowsCached) dirtyRows=\(metrics.dirtyRowsRequested) " +
            "suppressed=\(metrics.fullScrollDirtyRangesSuppressed) " +
            "fullRefreshGeneration=\(fullRefreshGenerationBefore)->\(fullRefreshGenerationAfter) " +
            "lineInfoGeneration=\(lineInfoGenerationBefore)->\(lineInfoGenerationAfter)"
        )
        #expect(metrics.rowsRemapped > 0)
        #expect(metrics.dirtyRowsRequested == 12)
        #expect(metrics.fullScrollDirtyRangesSuppressed == 1)
        #expect(fullRefreshGenerationAfter == fullRefreshGenerationBefore)
        #expect(lineInfoGenerationAfter == lineInfoGenerationBefore)
        #expect(snapshotsEqual)
    }

    @Test func perRowLineInfoInvalidationRebuildsWithoutDirtyTransfer() throws {
        let (view, renderer) = makeHarness()
        view.linkHighlightMode = .hover
        let linkLine = "https://example.com cached link\r\n"
        view.terminal.feed(text: String(repeating: linkLine, count: 40))
        transferTerminalDirtyRange(to: view)
        _ = renderer.debugBuildSnapshot(scale: 1)

        let buffer = view.terminal.displayBuffer
        let targetRow = buffer.yDisp + 5
        let match = try #require(
            view.terminal.linkMatch(
                at: .buffer(Position(col: 5, row: targetRow)),
                mode: .explicitAndImplicit
            )
        )
        renderer.debugResetMetrics()
        view.linkHighlightRange = match.rowRanges
        view.invalidateLineInfoCache(row: targetRow)

        let optimized = renderer.debugBuildSnapshot(scale: 1)
        let metrics = renderer.debugMetricsSnapshot()
        let forced = renderer.debugBuildSnapshot(scale: 1, forceFullRebuild: true)
        let snapshotsEqual = optimized == forced

        print(
            "REDTEAM2_LINE_INFO_NO_DIRTY snapshotsEqual=\(snapshotsEqual) " +
            "rowsRebuilt=\(metrics.rowsRebuilt) rowsCached=\(metrics.rowsCached) " +
            "dirtyRows=\(metrics.dirtyRowsRequested)"
        )
        #expect(metrics.rowsRebuilt == 1)
        #expect(metrics.rowsCached == 11)
        #expect(metrics.dirtyRowsRequested == 0)
        #expect(snapshotsEqual)
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

    private func cachedLineFontSizes(in view: TerminalView) -> [CGFloat] {
        Array(Set(view.lineInfoCache.values.flatMap { info in
            info.info.segments.compactMap { segment -> CGFloat? in
                guard segment.attributedString.length > 0 else { return nil }
                return (segment.attributedString.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize
            }
        })).sorted()
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
