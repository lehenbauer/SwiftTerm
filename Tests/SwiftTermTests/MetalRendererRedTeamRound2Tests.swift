//
//  MetalRendererRedTeamRound2Tests.swift
//
//  Fork red-team round 2, migrated to v1.99.2's renderer seams: incremental
//  Metal frames equal from-scratch rebuilds (`MetalRowCacheTests.Harness`),
//  font tables stay bounded, and font resets reach the renderer. The fork's
//  cache-entry counters (`debugMetricsSnapshot`) and line-info cache have no
//  v1.99.2 counterpart; their observable consequences are asserted instead.
//
#if os(macOS)
import AppKit
import Foundation
import Testing

@testable import SwiftTerm

@MainActor
@Suite(.serialized)
final class MetalRendererRedTeamRound2Tests {
    private static let rows = 12

    /// Rows the harness view actually shows (its frame sizes the grid).
    private func visibleRows(_ harness: MetalRowCacheTests.Harness) -> Int {
        harness.view.terminalDimensions.rows
    }

    private func makeHarness(scrollback: Int = 200) throws -> MetalRowCacheTests.Harness {
        try #require(MetalRowCacheTests.Harness(cols: 40, rows: 12, scrollback: scrollback))
    }

    private func optimizedAndTruth(_ harness: MetalRowCacheTests.Harness) async throws
        -> (MetalRowCacheTests.DrawnFrame, MetalRowCacheTests.DrawnFrame)
    {
        let optimized = try #require(await harness.frame())
        let truth = try #require(await harness.freshFrame())
        return (optimized, truth)
    }

    /// Point sizes of the fonts the CG text builder uses for the visible rows.
    private func renderedFontSizes(_ view: TerminalView) -> [CGFloat] {
        let snapshot = TerminalSnapshot()
        let viewState = FrameViewState(view: view)
        view.withTerminal { terminal in
            _ = snapshot.refresh(terminal: terminal, viewState: viewState,
                                 selection: SnapshotSelectionState(selection: view.selection))
        }
        let context = SnapshotRenderContext(viewState: viewState, snapshot: snapshot)
        var sizes = Set<CGFloat>()
        for (index, row) in snapshot.rows.enumerated() {
            let info = view.textBuilder.buildAttributedString(row: row, absoluteRow: snapshot.firstRow + index,
                                                              context: context)
            for segment in info.segments where segment.attributedString.length > 0 {
                if let font = segment.attributedString.attribute(.font, at: 0, effectiveRange: nil) as? NSFont {
                    sizes.insert(font.pointSize)
                }
            }
        }
        return sizes.sorted()
    }

    @Test(.enabled(if: MetalRowCacheTests.metalIsUsable, "needs Metal"))
    func fallbackFontRetentionStaysBoundedAcrossShaperChurn() async throws {
        let harness = try makeHarness(scrollback: 3_000)
        harness.view.feed(text: "warm fallback fonts 界🙂\r\n")
        _ = try #require(await harness.frame())
        let initialCount = harness.renderer.debugRasterFontRegistryCount
        var maximumCount = initialCount

        for frame in 0..<2_200 {
            harness.view.feed(text: "unique shaper key \(frame) 界🙂\r\n")
            _ = try #require(await harness.frame())
            maximumCount = max(maximumCount, harness.renderer.debugRasterFontRegistryCount)
        }

        let finalCount = harness.renderer.debugRasterFontRegistryCount
        #expect(finalCount <= initialCount + 2, "retained fonts \(initialCount) -> \(finalCount)")
        #expect(maximumCount <= initialCount + 2, "retained fonts peaked at \(maximumCount)")
    }

    /// A full-refresh change made after output scrolled (the fork's late
    /// refresh stamp) still rebuilds every row.
    @Test(.enabled(if: MetalRowCacheTests.metalIsUsable, "needs Metal"))
    func refreshStampBumpedAfterDirtyCaptureStillForcesFullRebuild() async throws {
        let harness = try makeHarness()
        let blockLine = "\u{2588}\u{2580}\u{2584}\u{258c}\u{2590} cached block glyphs\r\n"
        harness.view.feed(text: String(repeating: blockLine, count: 40))
        _ = try #require(await harness.frame())

        harness.view.feed(text: "scroll one row\r\n")
        harness.view.antiAliasCustomBlockGlyphs.toggle()
        let (optimized, truth) = try await optimizedAndTruth(harness)

        #expect(optimized.rebuilt == visibleRows(harness))
        #expect(optimized.rows == truth.rows)
        #expect(optimized.pixels == truth.pixels)
    }

    /// `resetFontSize` reaches the renderer: the frame changes, equals a
    /// cold rebuild, and draws at the new font size.
    @Test(.enabled(if: MetalRowCacheTests.metalIsUsable, "needs Metal"))
    func resetFontSizeUsesCoordinatedMetalCacheReset() async throws {
        let harness = try makeHarness()
        let view = harness.view
        view.font = NSFont.monospacedSystemFont(ofSize: 24, weight: .regular)
        view.resize(cols: 40, rows: Self.rows)
        view.feed(text: "font reset bypass probe\r\n")
        let before = try #require(await harness.frame())
        let beforeFontSize = view.font.pointSize
        let beforeCellDimension = try #require(view.cellDimension)

        view.resetFontSize()
        let afterFontSize = view.font.pointSize
        let afterCellDimension = try #require(view.cellDimension)
        let (after, truth) = try await optimizedAndTruth(harness)

        #expect(afterFontSize != beforeFontSize)
        #expect(afterCellDimension != beforeCellDimension)
        #expect(renderedFontSizes(view).contains(afterFontSize))
        #expect(!renderedFontSizes(view).contains(beforeFontSize))
        #expect(after.rows != before.rows)
        #expect(after.rows == truth.rows)
        #expect(after.pixels == truth.pixels)
    }

    @Test(.enabled(if: MetalRowCacheTests.metalIsUsable, "needs Metal"))
    func scrollCoalescedWithHoverLinkInvalidationMatchesFullRebuild() async throws {
        let harness = try makeHarness()
        let view = harness.view
        view.linkHighlightMode = .hover
        let linkLine = "https://example.com cached link\r\n"
        view.feed(text: String(repeating: linkLine, count: 40))
        _ = try #require(await harness.frame())

        view.feed(text: "scroll one row\r\n")
        let match = try #require(view.withTerminal { terminal in
            terminal.linkMatch(at: .buffer(Position(col: 5, row: terminal.displayBuffer.yDisp + 5)),
                               mode: .explicitAndImplicit)
        })
        view.linkHighlightRange = match.rowRanges
        view.invalidateLinkHighlight(oldRange: nil, newRange: match.rowRanges)
        let (optimized, truth) = try await optimizedAndTruth(harness)

        #expect(optimized.moved > 0, "scrolled rows should be reused, not rebuilt")
        #expect(optimized.rows == truth.rows)
        #expect(optimized.pixels == truth.pixels)
    }

    /// Highlighting one row's link rebuilds that row and reuses the others.
    @Test(.enabled(if: MetalRowCacheTests.metalIsUsable, "needs Metal"))
    func perRowLineInfoInvalidationRebuildsWithoutDirtyTransfer() async throws {
        let harness = try makeHarness()
        let view = harness.view
        view.linkHighlightMode = .hover
        let linkLine = "https://example.com cached link\r\n"
        view.feed(text: String(repeating: linkLine, count: 40))
        _ = try #require(await harness.frame())

        let match = try #require(view.withTerminal { terminal in
            terminal.linkMatch(at: .buffer(Position(col: 5, row: terminal.displayBuffer.yDisp + 5)),
                               mode: .explicitAndImplicit)
        })
        view.linkHighlightRange = match.rowRanges
        view.invalidateLinkHighlight(oldRange: nil, newRange: match.rowRanges)
        let (optimized, truth) = try await optimizedAndTruth(harness)

        #expect(optimized.rebuilt == 1)
        #expect(optimized.cached == visibleRows(harness) - 1)
        #expect(optimized.rows == truth.rows)
        #expect(optimized.pixels == truth.pixels)
    }
}
#endif
