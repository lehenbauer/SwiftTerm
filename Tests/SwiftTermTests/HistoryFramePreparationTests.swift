#if os(macOS)
import AppKit
import Testing
@testable import SwiftTerm

/// Exercises the snapshot owner's real CG frame decision, including cases
/// where independent appearance changes and live output share one frame.
@MainActor
struct HistoryFramePreparationTests {
    private func prepare(_ view: TerminalView) -> TerminalView.PreparedFrame? {
        view.renderOwner.prepareFrame(viewState: FrameViewState(view: view))
    }

    private func makeView() -> TerminalView {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 640, height: 320))
        let rows = view.terminalDimensions.rows
        for index in 0..<(rows * 4) {
            view.feed(text: "line \(index)\r\n")
        }
        _ = prepare(view)
        view.scrollTo(row: 0)
        _ = prepare(view)
        view.withTerminal { terminal in
            #expect(terminal.buffer.yBase - terminal.buffer.yDisp >= terminal.rows)
            terminal.clearUpdateRange()
        }
        return view
    }

    @Test func unrelatedLiveOutputHasNoHistoryRegion() throws {
        let view = makeView()
        let before = view.visibleRowsText(0..<view.terminalDimensions.rows)
        view.feed(text: "unseen live output")
        let frame = try #require(prepare(view))
        #expect(frame.region == nil)
        #expect(view.visibleRowsText(0..<view.terminalDimensions.rows) == before)
    }

    @Test func selectionChangeAndUnrelatedOutputStillRepaint() throws {
        let view = makeView()
        view.withTerminal { terminal in
            view.selection.setSelection(
                start: Position(col: 0, row: terminal.buffer.yDisp),
                end: Position(col: 4, row: terminal.buffer.yDisp))
        }
        view.feed(text: "unseen live output")
        let frame = try #require(prepare(view))
        #expect(frame.region == view.bounds)
    }

    @Test func explicitRefreshAndLiveOutputStillRepaint() throws {
        let view = makeView()
        view.requestFullDisplayRefresh()
        view.feed(text: "unseen live output")
        let frame = try #require(prepare(view))
        #expect(frame.region == view.bounds)
    }

    @Test func changedLiveRowOverlappingViewportStillRepaints() throws {
        let view = makeView()
        let bottom = view.withTerminal { $0.buffer.yBase }
        view.scrollTo(row: bottom - 2)
        _ = prepare(view)
        view.feed(text: "\u{1b}[1;1HX")
        let frame = try #require(prepare(view))
        #expect(frame.region == view.bounds)
    }

    @Test func capacityTrimAtOldestHistoryRowRepaintsChangedViewport() throws {
        let view = TerminalView(
            frame: CGRect(x: 0, y: 0, width: 640, height: 320), font: nil,
            terminalOptions: TerminalOptions(cols: 80, rows: 10, scrollback: 40),
            initialGeometry: .grid(cols: 80, rows: 10), autoResizeGrid: false)
        for index in 0..<100 { view.feed(text: "line \(index)\r\n") }
        view.scrollTo(row: 0)
        _ = prepare(view)
        let before = view.visibleRowsText(0..<10)
        let anchor = view.withTerminal { $0.buffer.linesTop }
        view.feed(text: "another line\r\n")
        let frame = try #require(prepare(view))
        #expect(view.withTerminal { $0.buffer.yDisp == 0 && $0.buffer.linesTop > anchor })
        #expect(view.visibleRowsText(0..<10) != before)
        #expect(frame.region == view.bounds)
    }

    @Test func frozenFrameCannotConsumePendingHistoryRefresh() throws {
        let view = makeView()
        view.feed(text: "\u{1b}[?2026h")
        view.requestFullDisplayRefresh()
        view.feed(text: "unseen live output")
        #expect(prepare(view) == nil)
        view.feed(text: "\u{1b}[?2026l")
        let frame = try #require(prepare(view))
        #expect(frame.region == view.bounds)
    }
}
#endif
