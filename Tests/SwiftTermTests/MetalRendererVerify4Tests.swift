#if os(macOS)
import AppKit
import Foundation
import Testing

@testable import SwiftTerm

@MainActor
@Suite(.serialized)
final class MetalRendererVerify4Tests {
    @Test func rejectedKittyPutReusesCachedRowsWithoutChangingOutput() {
        let (view, renderer) = makeDebugHarness()
        view.terminal.feed(text: "stable renderer content")
        transferTerminalDirtyRange(to: view)
        _ = renderer.debugBuildSnapshot(scale: 1)

        let pixels = Array(repeating: [UInt8](arrayLiteral: 255, 0, 0, 255), count: 4).flatMap { $0 }
        sendKitty(
            terminal: view.terminal,
            control: "a=t,f=32,s=2,v=2,t=d,i=42,q=2",
            payload: pixels
        )
        transferTerminalDirtyRange(to: view)
        let before = renderer.debugBuildSnapshot(scale: 1)
        let beforeGeneration = view.terminal.kittyGraphicsState.mutationGeneration
        renderer.debugResetMetrics()

        // The image lookup updates only its LRU access tick before the invalid
        // parent makes display fail. Access-tick bookkeeping must not advance the
        // render generation, so cached rows stay reusable.
        sendKitty(
            terminal: view.terminal,
            control: "a=p,i=42,p=21,P=999,Q=999,q=2"
        )

        let terminalDirty = view.terminal.getUpdateRange()
        let afterGeneration = view.terminal.kittyGraphicsState.mutationGeneration
        let after = renderer.debugBuildSnapshot(scale: 1)
        let metrics = renderer.debugMetricsSnapshot()
        let forced = renderer.debugBuildSnapshot(scale: 1, forceFullRebuild: true)

        print(
            "VERIFY4_KITTY_REJECTED_PUT outputEqual=\(before == after) " +
            "forcedEqual=\(after == forced) generation=\(beforeGeneration)->\(afterGeneration) " +
            "placements=\(view.terminal.kittyGraphicsState.placementsByKey.count) " +
            "terminalDirty=\(String(describing: terminalDirty)) " +
            "rowsRebuilt=\(metrics.rowsRebuilt) rowsCached=\(metrics.rowsCached) " +
            "dirtyRows=\(metrics.dirtyRowsRequested) " +
            "signatureInvalidations=\(metrics.signatureInvalidations)"
        )

        #expect(before == after)
        #expect(after == forced)
        #expect(afterGeneration == beforeGeneration)
        #expect(view.terminal.kittyGraphicsState.placementsByKey.isEmpty)
        #expect(terminalDirty == nil)
        #expect(metrics.rowsRebuilt == 0)
        #expect(metrics.rowsCached == 12)
        #expect(metrics.dirtyRowsRequested == 0)
        #expect(metrics.signatureInvalidations == 0)
    }

    @Test func defaultFontSetterStillSoftResetsTerminalModes() {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        view.resize(cols: 40, rows: 12)
        view.terminal.feed(text: "\u{1b}[?1h\u{1b}[?6h\u{1b}[?25l\u{1b}[4h")
        let before = terminalModeSummary(view)

        view.font = NSFont.monospacedSystemFont(ofSize: view.font.pointSize, weight: .regular)
        let after = terminalModeSummary(view)

        print("VERIFY4_DEFAULT_FONT_RESET before=\(before) after=\(after)")

        #expect(before == "appCursor=true origin=true hidden=true insert=true")
        #expect(after == "appCursor=false origin=false hidden=false insert=false")
    }

    private func makeDebugHarness() -> (TerminalView, MetalTerminalRenderer) {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        view.resize(cols: 40, rows: 12)
        view.terminal.changeScrollback(200)
        view.frame.size = CGSize(width: view.cellDimension.width * 40,
                                 height: view.cellDimension.height * 12)
        let renderer = MetalTerminalRenderer(debugTerminalView: view)
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

    private func terminalModeSummary(_ view: TerminalView) -> String {
        let terminal = view.terminal!
        return "appCursor=\(terminal.applicationCursor) origin=\(terminal.originMode) " +
            "hidden=\(terminal.cursorHidden) insert=\(terminal.insertMode)"
    }
}
#endif
