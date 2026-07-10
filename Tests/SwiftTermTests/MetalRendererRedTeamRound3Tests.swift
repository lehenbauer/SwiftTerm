#if os(macOS)
import AppKit
import Foundation
import MetalKit
import Testing

@testable import SwiftTerm

@MainActor
@Suite(.serialized)
final class MetalRendererRedTeamRound3Tests {
    @Test func replacingVirtualPlacementInPlaceInvalidatesCachedRows() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            return
        }
        let (view, renderer) = try makeMetalHarness()
        let imageId: UInt32 = 42
        let placementId: UInt32 = 21
        let pixels = Array(repeating: [UInt8](arrayLiteral: 255, 0, 0, 255), count: 4).flatMap { $0 }

        sendKitty(
            terminal: view.terminal,
            control: "a=T,f=32,s=2,v=2,t=d,c=1,r=1,i=\(imageId),p=\(placementId),U=1",
            payload: pixels
        )
        feedPlaceholder(terminal: view.terminal, imageId: imageId, placementId: placementId)
        transferTerminalDirtyRange(to: view)
        _ = renderer.debugBuildSnapshot(scale: 1)

        let beforeLineGeneration = view.terminal.displayBuffer.lines[0].generation
        let beforeStamp = kittyStamp(view.terminal)
        renderer.debugResetMetrics()

        sendKitty(
            terminal: view.terminal,
            control: "a=p,i=\(imageId),p=\(placementId),U=1,c=2,r=1"
        )
        transferTerminalDirtyRange(to: view)

        let afterLineGeneration = view.terminal.displayBuffer.lines[0].generation
        let afterStamp = kittyStamp(view.terminal)
        let optimized = renderer.debugBuildSnapshot(scale: 1)
        let metrics = renderer.debugMetricsSnapshot()
        let forced = renderer.debugBuildSnapshot(scale: 1, forceFullRebuild: true)
        let snapshotsEqual = optimized == forced

        print(
            "REDTEAM3_VIRTUAL_PLACEMENT_REPLACE snapshotsEqual=\(snapshotsEqual) " +
            "lineGeneration=\(beforeLineGeneration)->\(afterLineGeneration) " +
            "kittyStamp=\(beforeStamp)->\(afterStamp) rowsRebuilt=\(metrics.rowsRebuilt) " +
            "rowsCached=\(metrics.rowsCached) dirtyRows=\(metrics.dirtyRowsRequested) " +
            "optimizedPlaceholder=\(placeholderVertexSummary(optimized)) " +
            "forcedPlaceholder=\(placeholderVertexSummary(forced))"
        )

        #expect(beforeLineGeneration == afterLineGeneration)
        #expect(beforeStamp != afterStamp)
        #expect(metrics.rowsRebuilt == 12)
        #expect(metrics.dirtyRowsRequested == 0)
        #expect(snapshotsEqual)
    }

    @Test func kittyPayloadTailChangeInvalidatesSnapshotAndTextureCache() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            return
        }
        let (view, renderer) = try makeMetalHarness()
        let imageId: UInt32 = 42
        let placementId: UInt32 = 21
        var original = Array(repeating: UInt8(0), count: 5 * 4 * 4)
        for alpha in stride(from: 3, to: original.count, by: 4) {
            original[alpha] = 255
        }

        sendKitty(
            terminal: view.terminal,
            control: "a=T,f=32,s=5,v=4,t=d,c=1,r=1,i=\(imageId),p=\(placementId),U=1",
            payload: original
        )
        feedPlaceholder(terminal: view.terminal, imageId: imageId, placementId: placementId)
        transferTerminalDirtyRange(to: view)
        let before = renderer.debugBuildSnapshot(scale: 1)
        let beforeTexture = try #require(firstPlaceholderTexture(before))

        var replacement = original
        replacement[68] = 255
        sendKitty(
            terminal: view.terminal,
            control: "a=t,f=32,s=5,v=4,t=d,i=\(imageId)",
            payload: replacement
        )
        transferTerminalDirtyRange(to: view)

        let storedTailChanged = storedRgbaBytes(view.terminal, imageId: imageId)?[68] == 255
        let forced = renderer.debugBuildSnapshot(scale: 1, forceFullRebuild: true)
        let forcedTexture = try #require(firstPlaceholderTexture(forced))
        let snapshotsEqual = before == forced
        let textureIdentityEqual = beforeTexture == forcedTexture

        print(
            "REDTEAM3_KITTY_PAYLOAD_TAIL_COLLISION sourceTailChanged=\(storedTailChanged) " +
            "snapshotsEqual=\(snapshotsEqual) textureIdentityEqual=\(textureIdentityEqual) " +
            "byteCount=\(replacement.count) differingByte=68 hashedPayload=full"
        )

        #expect(storedTailChanged)
        #expect(!snapshotsEqual)
        #expect(!textureIdentityEqual)
    }

    @Test func resetFontSizePreservesTerminalModesAndClearsSelection() throws {
        let (view, _) = makeDebugHarness()
        view.font = NSFont.monospacedSystemFont(ofSize: 24, weight: .regular)
        view.terminal.feed(text: "mode preservation probe")
        view.terminal.feed(text: "\u{1b}[?1h\u{1b}[?6h\u{1b}[?25l\u{1b}[4h")
        view.selection.setSelection(start: Position(col: 0, row: 0),
                                    end: Position(col: 4, row: 0))

        let before = terminalModeSummary(view)
        view.resetFontSize()
        let after = terminalModeSummary(view)

        print("REDTEAM3_RESET_FONT_SIZE_SIDE_EFFECT before=\(before) after=\(after)")

        #expect(before == "appCursor=true origin=true hidden=true insert=true selection=true")
        #expect(after == "appCursor=true origin=true hidden=true insert=true selection=false")
    }

    @Test func deselectionRebuildsPreviouslyHighlightedRows() throws {
        let (view, renderer) = makeDebugHarness()
        view.terminal.feed(text: String(repeating: "selection repaint row\r\n", count: 30))
        transferTerminalDirtyRange(to: view)
        _ = renderer.debugBuildSnapshot(scale: 1)

        view.metalView = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        let yDisp = view.terminal.displayBuffer.yDisp
        view.selection.setSelection(start: Position(col: 1, row: yDisp + 2),
                                    end: Position(col: 10, row: yDisp + 4))
        let selected = renderer.debugBuildSnapshot(scale: 1)

        renderer.debugResetMetrics()
        view.selection.selectNone()
        let deselected = renderer.debugBuildSnapshot(scale: 1)
        let metrics = renderer.debugMetricsSnapshot()
        let forced = renderer.debugBuildSnapshot(scale: 1, forceFullRebuild: true)
        let snapshotsEqual = deselected == forced

        print(
            "REDTEAM3_DESELECTION snapshotsEqual=\(snapshotsEqual) " +
            "selectedChanged=\(selected != deselected) rowsRebuilt=\(metrics.rowsRebuilt) " +
            "dirtyRows=\(metrics.dirtyRowsRequested) selectionActive=\(view.selection.active)"
        )

        #expect(selected != deselected)
        #expect(metrics.rowsRebuilt == 12)
        #expect(metrics.dirtyRowsRequested == 12)
        #expect(!view.selection.active)
        #expect(snapshotsEqual)
    }

    @Test func cursorMoveRebuildsCursorButReusesUnderlyingRows() throws {
        let (view, renderer) = makeDebugHarness()
        view.terminal.feed(text: "cursor under-cell probe")
        transferTerminalDirtyRange(to: view)
        let before = renderer.debugBuildSnapshot(scale: 1)

        renderer.debugResetMetrics()
        view.terminal.feed(text: "\u{1b}[5D")
        transferTerminalDirtyRange(to: view)
        let moved = renderer.debugBuildSnapshot(scale: 1)
        let metrics = renderer.debugMetricsSnapshot()
        let forced = renderer.debugBuildSnapshot(scale: 1, forceFullRebuild: true)

        let rowsEqual = before.rows == moved.rows
        let cursorChanged = before.cursorColors != moved.cursorColors ||
            before.cursorGlyphsGray != moved.cursorGlyphsGray ||
            before.cursorGlyphsColor != moved.cursorGlyphsColor
        let snapshotsEqual = moved == forced
        print(
            "REDTEAM3_CURSOR_MOVE snapshotsEqual=\(snapshotsEqual) rowsEqual=\(rowsEqual) " +
            "cursorChanged=\(cursorChanged) rowsRebuilt=\(metrics.rowsRebuilt) " +
            "rowsCached=\(metrics.rowsCached) dirtyRows=\(metrics.dirtyRowsRequested)"
        )

        #expect(rowsEqual)
        #expect(cursorChanged)
        #expect(metrics.rowsRebuilt == 0)
        #expect(metrics.rowsCached == 12)
        #expect(snapshotsEqual)
    }

    @Test func recycledBufferLineIdentityCannotHitStaleGeneration() throws {
        let (view, renderer) = makeDebugHarness(scrollback: 0)
        view.terminal.feed(text: String(repeating: "capacity recycle row\r\n", count: 20))
        transferTerminalDirtyRange(to: view)
        _ = renderer.debugBuildSnapshot(scale: 1)

        let buffer = view.terminal.displayBuffer
        let recycledLine = buffer.lines[0]
        let generationBefore = recycledLine.generation
        view.invalidateLineInfoCache(row: 0)
        renderer.debugResetMetrics()

        view.terminal.feed(text: "identity recycle trigger\r\n")
        transferTerminalDirtyRange(to: view)
        let identityReused = buffer.lines[buffer.lines.count - 1] === recycledLine
        let generationAfter = recycledLine.generation
        let optimized = renderer.debugBuildSnapshot(scale: 1)
        let metrics = renderer.debugMetricsSnapshot()
        let forced = renderer.debugBuildSnapshot(scale: 1, forceFullRebuild: true)
        let snapshotsEqual = optimized == forced

        print(
            "REDTEAM3_RECYCLED_LINE_IDENTITY identityReused=\(identityReused) " +
            "generation=\(generationBefore)->\(generationAfter) snapshotsEqual=\(snapshotsEqual) " +
            "rowsRemapped=\(metrics.rowsRemapped) rowsRebuilt=\(metrics.rowsRebuilt) " +
            "rowsCached=\(metrics.rowsCached) invalidationTable=\(view.lineInfoInvalidationGenerations.count)"
        )

        #expect(identityReused)
        #expect(generationAfter > generationBefore)
        #expect(snapshotsEqual)
    }

    private func makeDebugHarness(scrollback: Int = 200) -> (TerminalView, MetalTerminalRenderer) {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        view.resize(cols: 40, rows: 12)
        view.terminal.changeScrollback(scrollback)
        view.frame.size = CGSize(width: view.cellDimension.width * 40,
                                 height: view.cellDimension.height * 12)
        let renderer = MetalTerminalRenderer(debugTerminalView: view)
        view.metalRenderer = renderer
        return (view, renderer)
    }

    private func makeMetalHarness() throws -> (TerminalView, MetalTerminalRenderer) {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        view.resize(cols: 40, rows: 12)
        view.terminal.changeScrollback(200)
        view.frame.size = CGSize(width: view.cellDimension.width * 40,
                                 height: view.cellDimension.height * 12)
        let metalView = MTKView(frame: view.bounds, device: device)
        let renderer = try MetalTerminalRenderer(view: metalView, terminalView: view)
        view.metalView = metalView
        view.metalRenderer = renderer
        return (view, renderer)
    }

    private func sendKitty(terminal: Terminal, control: String, payload: [UInt8]? = nil) {
        let sequence: String
        if let payload {
            sequence = "\u{1b}_G\(control);\(Data(payload).base64EncodedString())\u{1b}\\"
        } else {
            sequence = "\u{1b}_G\(control)\u{1b}\\"
        }
        terminal.feed(text: sequence)
    }

    private func feedPlaceholder(terminal: Terminal, imageId: UInt32, placementId: UInt32) {
        precondition(imageId < 256 && placementId < 256)
        terminal.feed(
            text: "\u{1b}[38;5;\(imageId)m\u{1b}[58;5;\(placementId)m" +
                "\u{10EEEE}\u{0305}\u{0305}"
        )
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

    private func kittyStamp(_ terminal: Terminal) -> String {
        let state = terminal.kittyGraphicsState
        return "\(state.imagesById.count)/\(state.placementsByKey.count)/\(state.nextImageId)/\(state.nextPlacementId)/\(state.mutationGeneration)"
    }

    private func placeholderVertexSummary(_ snapshot: MetalRendererDebugDrawSnapshot) -> String {
        let vertices = snapshot.rows.flatMap(\.placeholderImages).flatMap(\.vertices)
        guard !vertices.isEmpty else { return "none" }
        return "count=\(vertices.count),minX=\(vertices.enumerated().filter { $0.offset % 8 == 0 }.map(\.element).min() ?? 0),maxX=\(vertices.enumerated().filter { $0.offset % 8 == 0 }.map(\.element).max() ?? 0)"
    }

    private func firstPlaceholderTexture(_ snapshot: MetalRendererDebugDrawSnapshot) -> ObjectIdentifier? {
        snapshot.rows.lazy.flatMap(\.placeholderImages).first?.texture
    }

    private func storedRgbaBytes(_ terminal: Terminal, imageId: UInt32) -> [UInt8]? {
        guard let image = terminal.kittyGraphicsState.imagesById[imageId] else { return nil }
        guard case .rgba(let bytes, _, _) = image.payload else { return nil }
        return bytes
    }

    private func terminalModeSummary(_ view: TerminalView) -> String {
        let terminal = view.terminal!
        return "appCursor=\(terminal.applicationCursor) origin=\(terminal.originMode) " +
            "hidden=\(terminal.cursorHidden) insert=\(terminal.insertMode) " +
            "selection=\(view.selection.active)"
    }
}
#endif
