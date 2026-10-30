//
//  MetalRendererRedTeamTests.swift
//
//  Fork red-team invariants for the Metal renderer's incremental row cache,
//  migrated to v1.99.2: every optimized frame must equal a from-scratch
//  rebuild of the same state (`MetalRowCacheTests.Harness.freshFrame`), and
//  a change that affects every visible row must rebuild every visible row.
//  The fork's line-info and full-refresh generation probes were mechanism
//  counters that v1.99.2 does not have; the observable frame equality and
//  row counts they guarded are kept.
//
#if os(macOS)
import AppKit
import Foundation
import Testing

@testable import SwiftTerm

@MainActor
@Suite(.serialized)
final class MetalRendererRedTeamTests {
    private static let rows = 12

    /// Rows the harness view actually shows (its frame sizes the grid).
    private func visibleRows(_ harness: MetalRowCacheTests.Harness) -> Int {
        harness.view.terminalDimensions.rows
    }
    private let blockLine = "\u{2588}\u{2580}\u{2584}\u{258c}\u{2590} cached block glyphs\r\n"

    private func makeHarness(scrollback: Int = 200) throws -> MetalRowCacheTests.Harness {
        try #require(MetalRowCacheTests.Harness(cols: 40, rows: 12, scrollback: scrollback))
    }

    /// Renders the current state incrementally, then from scratch.
    private func optimizedAndTruth(_ harness: MetalRowCacheTests.Harness) async throws
        -> (MetalRowCacheTests.DrawnFrame, MetalRowCacheTests.DrawnFrame)
    {
        let optimized = try #require(await harness.frame())
        let truth = try #require(await harness.freshFrame())
        return (optimized, truth)
    }

    @Test(.enabled(if: MetalRowCacheTests.metalIsUsable, "needs Metal"))
    func blockAntialiasToggleWithoutScrollMatchesFullRebuild() async throws {
        let harness = try makeHarness()
        harness.view.feed(text: String(repeating: blockLine, count: 40))
        _ = try #require(await harness.frame())

        harness.view.antiAliasCustomBlockGlyphs.toggle()
        let (optimized, truth) = try await optimizedAndTruth(harness)

        #expect(optimized.moved == 0)
        #expect(optimized.rebuilt == visibleRows(harness))
        #expect(optimized.rows == truth.rows)
        #expect(optimized.pixels == truth.pixels)
    }

    @Test(.enabled(if: MetalRowCacheTests.metalIsUsable, "needs Metal"))
    func scrollCoalescedWithBlockAntialiasToggleMatchesFullRebuild() async throws {
        let harness = try makeHarness()
        harness.view.feed(text: String(repeating: blockLine, count: 40))
        _ = try #require(await harness.frame())

        harness.view.feed(text: "scroll one row\r\n")
        harness.view.antiAliasCustomBlockGlyphs.toggle()
        let (optimized, truth) = try await optimizedAndTruth(harness)

        #expect(optimized.rebuilt == visibleRows(harness))
        #expect(optimized.rows == truth.rows)
        #expect(optimized.pixels == truth.pixels)
    }

    @Test(.enabled(if: MetalRowCacheTests.metalIsUsable, "needs Metal"))
    func scrollCoalescedWithCustomBlockToggleMatchesFullRebuild() async throws {
        let harness = try makeHarness()
        harness.view.feed(text: String(repeating: blockLine, count: 40))
        _ = try #require(await harness.frame())

        harness.view.feed(text: "scroll one row\r\n")
        harness.view.customBlockGlyphs.toggle()
        let (optimized, truth) = try await optimizedAndTruth(harness)

        #expect(optimized.rebuilt == visibleRows(harness))
        #expect(optimized.rows == truth.rows)
        #expect(optimized.pixels == truth.pixels)
    }

    @Test(.enabled(if: MetalRowCacheTests.metalIsUsable, "needs Metal"))
    func scrollCoalescedWithBrightColorToggleMatchesFullRebuild() async throws {
        let harness = try makeHarness()
        let brightLine = "\u{1b}[91mbright cached text\u{1b}[0m\r\n"
        harness.view.feed(text: String(repeating: brightLine, count: 40))
        _ = try #require(await harness.frame())

        harness.view.feed(text: "scroll one row\r\n")
        harness.view.useBrightColors.toggle()
        let (optimized, truth) = try await optimizedAndTruth(harness)

        #expect(optimized.rebuilt == visibleRows(harness))
        #expect(optimized.rows == truth.rows)
        #expect(optimized.pixels == truth.pixels)
    }

    /// A full-refresh change with no terminal dirty rows still rebuilds every
    /// visible row.
    @Test(.enabled(if: MetalRowCacheTests.metalIsUsable, "needs Metal"))
    func fullRefreshInvalidatesRowsWithoutDirtyTransfer() async throws {
        let harness = try makeHarness()
        harness.view.feed(text: String(repeating: blockLine, count: 40))
        _ = try #require(await harness.frame())
        harness.view.withTerminal { $0.clearUpdateRange() }

        harness.view.antiAliasCustomBlockGlyphs.toggle()
        let (optimized, truth) = try await optimizedAndTruth(harness)

        #expect(optimized.rebuilt == visibleRows(harness))
        #expect(optimized.rows == truth.rows)
        #expect(optimized.pixels == truth.pixels)
    }

    /// Font smoothing changes rasterized glyphs, so every row is rebuilt and
    /// the frame equals a cold render.
    @Test(.enabled(if: MetalRowCacheTests.metalIsUsable, "needs Metal"))
    func fontSmoothingInvalidatesRasterizedGlyphRows() async throws {
        let harness = try makeHarness()
        harness.view.feed(text: String(repeating: "cached glyph text\r\n", count: 40))
        let before = try #require(await harness.frame())

        harness.view.fontSmoothing.toggle()
        let (optimized, truth) = try await optimizedAndTruth(harness)

        #expect(optimized.rebuilt == visibleRows(harness))
        #expect(optimized.pixels == truth.pixels)
        #expect(optimized.pixels != before.pixels, "control: smoothing must change rasterized glyphs")
    }

    /// The renderer's font tables stay bounded across many font changes.
    @Test(.enabled(if: MetalRowCacheTests.metalIsUsable, "needs Metal"))
    func retainedFontTableIsBoundedAcrossFontChanges() async throws {
        let harness = try makeHarness()
        harness.view.feed(text: "font cache probe\r\n")
        _ = try #require(await harness.frame())
        let initialCount = harness.renderer.debugRasterFontRegistryCount
        var maximumCount = initialCount

        for pointSize in 8..<40 {
            harness.view.font = NSFont.monospacedSystemFont(ofSize: CGFloat(pointSize), weight: .regular)
            harness.view.resize(cols: 40, rows: Self.rows)
            _ = try #require(await harness.frame())
            maximumCount = max(maximumCount, harness.renderer.debugRasterFontRegistryCount)
        }

        let finalCount = harness.renderer.debugRasterFontRegistryCount
        #expect(finalCount <= initialCount + 1, "font table grew \(initialCount) -> \(finalCount)")
        #expect(maximumCount <= initialCount + 1, "font table peaked at \(maximumCount)")
    }

    @Test(.enabled(if: MetalRowCacheTests.metalIsUsable, "needs Metal"))
    func circularScrollbackRotationMatchesFullRebuild() async throws {
        let harness = try makeHarness(scrollback: 20)
        for line in 0..<100 {
            harness.view.feed(text: "prefill \(line)\r\n")
        }
        _ = try #require(await harness.frame())
        let initialYDisp = harness.view.withTerminal { $0.displayBuffer.yDisp }
        var mismatches = 0

        for line in 0..<30 {
            harness.view.feed(text: "rotate \(line)\r\n")
            let (optimized, truth) = try await optimizedAndTruth(harness)
            if optimized.rows != truth.rows || optimized.pixels != truth.pixels {
                mismatches += 1
            }
        }

        let finalYDisp = harness.view.withTerminal { $0.displayBuffer.yDisp }
        #expect(finalYDisp == initialYDisp)
        #expect(mismatches == 0)
    }
}
#endif
