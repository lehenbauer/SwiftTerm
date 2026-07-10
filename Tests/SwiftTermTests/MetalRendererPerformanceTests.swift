#if os(macOS)
import Foundation
import MetalKit
import Testing

@testable import SwiftTerm

@MainActor
@Suite(.serialized)
final class MetalRendererPerformanceTests {
    private struct Harness {
        let view: TerminalView
        let renderer: MetalTerminalRenderer
    }

    private struct BenchmarkResult {
        let mode: String
        let frames: Int
        let initialYDisp: Int
        let finalYDisp: Int
        let buildMilliseconds: Double
        let metrics: MetalRendererDebugMetrics
    }

    @Test func scrollingDrawDataBenchmark() throws {
        let legacy = try runScrollingBenchmark(legacyMode: true)
        let optimized = try runScrollingBenchmark(legacyMode: false)
        printBenchmark(legacy)
        printBenchmark(optimized)

        #expect(legacy.metrics.buildCalls == legacy.frames)
        #expect(optimized.metrics.buildCalls == optimized.frames)
        #expect(legacy.finalYDisp > legacy.initialYDisp)
        #expect(optimized.finalYDisp > optimized.initialYDisp)
        #expect(legacy.metrics.visibleRows == legacy.frames * 60)
        #expect(optimized.metrics.visibleRows == optimized.frames * 60)
        #expect(legacy.metrics.rowsRebuilt >= optimized.metrics.rowsRebuilt * 5)
        #expect(legacy.metrics.postScriptNameCalls > 0)
        #expect(optimized.metrics.postScriptNameCalls == 0)
    }

    private func runScrollingBenchmark(legacyMode: Bool) throws -> BenchmarkResult {
        let harness = try makeHarness(scrollback: 20_000)
        prefill(harness, lineCount: 20_000)
        harness.renderer.debugSetLegacyBenchmarkMode(legacyMode)
        _ = harness.renderer.debugBuildSnapshot(scale: 1)
        harness.renderer.debugResetMetrics()

        let frames = 120
        var buildNanoseconds: UInt64 = 0
        let initialYDisp = harness.view.terminal.displayBuffer.yDisp
        for _ in 0..<frames {
            harness.view.terminal.feed(text: benchmarkLine)
            markTerminalDirty(harness.view)
            let start = DispatchTime.now().uptimeNanoseconds
            harness.renderer.debugBuildOnly(scale: 1)
            buildNanoseconds += DispatchTime.now().uptimeNanoseconds - start
        }

        let metrics = harness.renderer.debugMetricsSnapshot()
        let finalYDisp = harness.view.terminal.displayBuffer.yDisp
        let buildMilliseconds = Double(buildNanoseconds) / 1_000_000
        return BenchmarkResult(mode: legacyMode ? "bf99f8e" : "optimized",
                               frames: frames,
                               initialYDisp: initialYDisp,
                               finalYDisp: finalYDisp,
                               buildMilliseconds: buildMilliseconds,
                               metrics: metrics)
    }

    private func printBenchmark(_ result: BenchmarkResult) {
        let metrics = result.metrics
        let averageRows = Double(metrics.rowsRebuilt) / Double(result.frames)
        print(
            "METAL_RENDERER_SCROLL_BENCHMARK " +
            "mode=\(result.mode) frames=\(result.frames) cols=80 rows=60 scrollback=20000 " +
            "initialYDisp=\(result.initialYDisp) finalYDisp=\(result.finalYDisp) " +
            String(format: "buildMs=%.3f avgBuildMs=%.3f avgRowsRebuilt=%.3f ",
                   result.buildMilliseconds,
                   result.buildMilliseconds / Double(result.frames),
                   averageRows) +
            "rowsRebuilt=\(metrics.rowsRebuilt) rowsCached=\(metrics.rowsCached) " +
            "maxRowsRebuilt=\(metrics.maxRowsRebuiltPerBuild) dirtyRows=\(metrics.dirtyRowsRequested) " +
            "signatureInvalidations=\(metrics.signatureInvalidations) " +
            "yDispOnlyInvalidations=\(metrics.yDispOnlySignatureInvalidations) " +
            "yDispChanges=\(metrics.yDispChanges) scrollRemapBuilds=\(metrics.scrollRemapBuilds) " +
            "rowsRemapped=\(metrics.rowsRemapped) " +
            "noDirtyBuilds=\(metrics.buildsWithoutDirtyRows) " +
            "glyphHits=\(metrics.glyphCacheHits) glyphMisses=\(metrics.glyphCacheMisses) " +
            "scaledFontHits=\(metrics.scaledFontCacheHits) scaledFontMisses=\(metrics.scaledFontCacheMisses) " +
            "shaperHits=\(metrics.shaperCacheHits) shaperMisses=\(metrics.shaperCacheMisses) " +
            "postScriptNameCalls=\(metrics.postScriptNameCalls)"
        )
    }

    @Test func scrollingOptimizedDrawDataMatchesForcedFullRebuild() throws {
        let harness = try makeHarness(scrollback: 20_000)
        prefill(harness, lineCount: 400)
        _ = harness.renderer.debugBuildSnapshot(scale: 1)

        for _ in 0..<8 {
            harness.view.terminal.feed(text: benchmarkLine)
            markTerminalDirty(harness.view)
            let optimized = harness.renderer.debugBuildSnapshot(scale: 1)
            let full = harness.renderer.debugBuildSnapshot(scale: 1, forceFullRebuild: true)
            #expect(optimized == full)
        }
    }

    @Test func alternateBufferOptimizedDrawDataMatchesForcedFullRebuild() throws {
        let harness = try makeHarness(scrollback: 20_000)
        harness.view.terminal.feed(text: "\u{1b}[?1049h")
        prefill(harness, lineCount: 80)
        _ = harness.renderer.debugBuildSnapshot(scale: 1)

        for _ in 0..<8 {
            harness.view.terminal.feed(text: benchmarkLine)
            markTerminalDirty(harness.view)
            let optimized = harness.renderer.debugBuildSnapshot(scale: 1)
            let full = harness.renderer.debugBuildSnapshot(scale: 1, forceFullRebuild: true)
            #expect(optimized == full)
        }
    }

    @Test func scrollingWithActiveSelectionMatchesForcedFullRebuild() throws {
        let harness = try makeHarness(scrollback: 20_000)
        prefill(harness, lineCount: 400)
        _ = harness.renderer.debugBuildSnapshot(scale: 1)
        harness.view.allowMouseReporting = false
        let yDisp = harness.view.terminal.displayBuffer.yDisp
        harness.view.selection.setSelection(start: Position(col: 2, row: yDisp + 10),
                                            end: Position(col: 20, row: yDisp + 12))

        harness.view.terminal.feed(text: benchmarkLine)
        markTerminalDirty(harness.view)
        let optimized = harness.renderer.debugBuildSnapshot(scale: 1)
        let full = harness.renderer.debugBuildSnapshot(scale: 1, forceFullRebuild: true)
        #expect(optimized == full)
    }

    @Test func metalViewUsesOnDemandScheduling() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            return
        }
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        try view.setUseMetal(true)
        defer { try? view.setUseMetal(false) }

        let metalView = try #require(view.metalView)
        #expect(metalView.isPaused)
        #expect(metalView.enableSetNeedsDisplay)
    }

    private var benchmarkLine: String {
        "0123456789 abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ\r\n"
    }

    private func makeHarness(scrollback: Int) throws -> Harness {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        view.resize(cols: 80, rows: 60)
        view.terminal.changeScrollback(scrollback)
        view.frame.size = CGSize(width: view.cellDimension.width * 80,
                                 height: view.cellDimension.height * 60)
        let renderer = MetalTerminalRenderer(debugTerminalView: view)
        return Harness(view: view, renderer: renderer)
    }

    private func prefill(_ harness: Harness, lineCount: Int) {
        harness.view.terminal.feed(text: String(repeating: benchmarkLine, count: lineCount))
        markTerminalDirty(harness.view)
    }

    private func markTerminalDirty(_ view: TerminalView) {
        let terminal = view.terminal!
        guard let (rowStart, rowEnd) = terminal.getUpdateRange() else {
            view.metalDirtyRange = nil
            return
        }
        let buffer = terminal.displayBuffer
        let maxRow = buffer.lines.count - 1
        let start = max(0, min(buffer.yDisp + rowStart, maxRow))
        let end = max(0, min(buffer.yDisp + rowEnd, maxRow))
        view.metalDirtyRange = start <= end ? start...end : nil
        terminal.clearUpdateRange()
    }
}
#endif
