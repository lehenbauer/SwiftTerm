//
//  MetalRendererPerformanceTests.swift
//
//  Fork Metal scrolling invariants, migrated to v1.99.2's renderer seams.
//  The fork compared its row cache against a legacy rebuild-every-row mode
//  (`bf99f8e`) that v1.99.2 does not have; the full rebuild is now the
//  baseline: scrolling must rebuild at most a fifth of the rows a full
//  rebuild would (the fork's >= 5x ratio), keep the raster font table
//  stable, and every optimized frame must equal a from-scratch rebuild.
//
#if os(macOS)
import Foundation
import MetalKit
import Testing

@testable import SwiftTerm

@MainActor
@Suite(.serialized)
final class MetalRendererPerformanceTests {
    private var benchmarkLine: String {
        "0123456789 abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ 界🙂\r\n"
    }

    private func makeHarness(scrollback: Int) throws -> MetalRowCacheTests.Harness {
        try #require(MetalRowCacheTests.Harness(cols: 80, rows: 24, scrollback: scrollback))
    }

    @Test(.enabled(if: MetalRowCacheTests.metalIsUsable, "needs Metal"))
    func scrollingDrawDataBenchmark() async throws {
        let harness = try makeHarness(scrollback: 20_000)
        harness.view.feed(text: String(repeating: benchmarkLine, count: 20_000))
        _ = try #require(await harness.frame())
        let rows = harness.view.terminalDimensions.rows
        let initialFonts = harness.renderer.debugRasterFontRegistryCount
        let initialYDisp = harness.view.withTerminal { $0.displayBuffer.yDisp }

        let frames = 120
        var rebuilt = 0
        var drawNanoseconds: UInt64 = 0
        for _ in 0..<frames {
            harness.view.feed(text: benchmarkLine)
            let start = DispatchTime.now().uptimeNanoseconds
            let frame = try #require(await harness.frame())
            drawNanoseconds += DispatchTime.now().uptimeNanoseconds - start
            rebuilt += frame.rebuilt
        }
        let finalYDisp = harness.view.withTerminal { $0.displayBuffer.yDisp }

        print("METAL_RENDERER_SCROLL_BENCHMARK frames=\(frames) rows=\(rows) " +
              "rowsRebuilt=\(rebuilt) fullRebuildRows=\(frames * rows) " +
              String(format: "avgFrameMs=%.3f (includes 1 ms harness sleep)",
                     Double(drawNanoseconds) / 1_000_000 / Double(frames)))
        #expect(finalYDisp > initialYDisp)
        #expect(rebuilt * 5 <= frames * rows, "scrolling rebuilt \(rebuilt) of \(frames * rows) rows")
        #expect(harness.renderer.debugRasterFontRegistryCount == initialFonts)
    }

    @Test(.enabled(if: MetalRowCacheTests.metalIsUsable, "needs Metal"))
    func scrollingOptimizedDrawDataMatchesForcedFullRebuild() async throws {
        let harness = try makeHarness(scrollback: 20_000)
        harness.view.feed(text: String(repeating: benchmarkLine, count: 400))
        _ = try #require(await harness.frame())

        for _ in 0..<8 {
            harness.view.feed(text: benchmarkLine)
            let optimized = try #require(await harness.frame())
            let full = try #require(await harness.freshFrame())
            #expect(optimized.rows == full.rows)
            #expect(optimized.pixels == full.pixels)
        }
    }

    @Test(.enabled(if: MetalRowCacheTests.metalIsUsable, "needs Metal"))
    func alternateBufferOptimizedDrawDataMatchesForcedFullRebuild() async throws {
        let harness = try makeHarness(scrollback: 20_000)
        harness.view.feed(text: "\u{1b}[?1049h")
        harness.view.feed(text: String(repeating: benchmarkLine, count: 80))
        _ = try #require(await harness.frame())

        for _ in 0..<8 {
            harness.view.feed(text: benchmarkLine)
            let optimized = try #require(await harness.frame())
            let full = try #require(await harness.freshFrame())
            #expect(optimized.rows == full.rows)
            #expect(optimized.pixels == full.pixels)
        }
    }

    @Test(.enabled(if: MetalRowCacheTests.metalIsUsable, "needs Metal"))
    func scrollingWithActiveSelectionMatchesForcedFullRebuild() async throws {
        let harness = try makeHarness(scrollback: 20_000)
        harness.view.feed(text: String(repeating: benchmarkLine, count: 400))
        _ = try #require(await harness.frame())
        harness.view.allowMouseReporting = false
        harness.view.withTerminal { terminal in
            let yDisp = terminal.displayBuffer.yDisp
            harness.view.selection.setSelection(start: Position(col: 2, row: yDisp + 10),
                                                end: Position(col: 20, row: yDisp + 12))
        }

        harness.view.feed(text: benchmarkLine)
        let optimized = try #require(await harness.frame())
        let full = try #require(await harness.freshFrame())
        #expect(optimized.rows == full.rows)
        #expect(optimized.pixels == full.pixels)
    }

    @Test func metalViewUsesOnDemandScheduling() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            return
        }
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        try view.setUseMetal(true)
        defer { try? view.setUseMetal(false) }

        // Rendering is on demand on either surface: a paused MTKView redrawn
        // by setNeedsDisplay, or v1.99.2's layer surface, which never draws
        // until the frame driver submits a frame.
        let metalView = try #require(view.metalView)
        if let mtkView = metalView as? MTKView {
            #expect(mtkView.isPaused)
            #expect(mtkView.enableSetNeedsDisplay)
        } else {
            let layerView = try #require(metalView as? TerminalMetalLayerView)
            #expect(layerView.needsExternalDrawCall)
        }
    }
}
#endif
