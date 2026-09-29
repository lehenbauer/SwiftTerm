import Testing
@testable import SwiftTerm

struct Upstream119BufferIntegrationTests {
    @Test func clearingHistoryPreservesAbsoluteIdentityOfRetainedRows() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 16, rows: 3, scrollback: 20)
        for i in 0..<8 { terminal.feed(text: "row \(i)\r\n") }
        let buffer = terminal.buffer
        let firstLiveLine = buffer.lines[buffer.yBase]
        let firstLiveIdentity = buffer.totalLinesTrimmed + buffer.yBase
        let screen = TerminalTestHarness.visibleLinesText(buffer: buffer, terminal: terminal)
        #expect(buffer.yBase > 0)
        terminal.clearScrollback()
        #expect(buffer.lines[0] === firstLiveLine)
        #expect(buffer.totalLinesTrimmed == firstLiveIdentity)
        #expect(TerminalTestHarness.visibleLinesText(buffer: buffer, terminal: terminal) == screen)
        terminal.clearScrollback()
        #expect(buffer.totalLinesTrimmed == firstLiveIdentity)
    }

    @Test func clearingPrependedHistoryRestoresOriginalAbsoluteIdentity() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 16, rows: 3, scrollback: 20)
        terminal.feed(text: "live")
        #expect(terminal.prependScrollbackCapture(byteArray: Array("old1\r\nold2".utf8)[...]) == 2)
        #expect(terminal.buffer.totalLinesTrimmed == -2)
        terminal.clearScrollback()
        #expect(terminal.buffer.totalLinesTrimmed == 0)
    }

    @Test func clearHistoryTranslatesSurvivingSelectionsAndDropsRemovedSelections() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 16, rows: 3, scrollback: 20)
        for i in 0..<8 { terminal.feed(text: "row \(i)\r\n") }
        let live = SelectionService(terminal: terminal)
        let history = SelectionService(terminal: terminal)
        let row = terminal.buffer.yBase
        live.setSelection(start: Position(col: 0, row: row), end: Position(col: 5, row: row))
        history.setSelection(start: Position(col: 0, row: 0), end: Position(col: 5, row: 0))
        let liveText = live.getSelectedText()
        #expect(live.active && history.active)
        terminal.clearScrollback()
        #expect(live.active)
        #expect(live.start.row == 0)
        #expect(live.getSelectedText() == liveText)
        #expect(!history.active)
    }

    @Test func clearNormalHistoryLeavesAlternateSelectionUnchanged() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 16, rows: 3, scrollback: 20)
        for i in 0..<8 { terminal.feed(text: "row \(i)\r\n") }
        terminal.feed(text: "\u{1b}[?1049h\u{1b}[Halt")
        let selection = SelectionService(terminal: terminal)
        selection.setSelection(start: Position(col: 0, row: 0), end: Position(col: 3, row: 0))
        #expect(selection.getSelectedText() == "alt")
        terminal.clearScrollback()
        #expect(selection.active)
        #expect(selection.getSelectedText() == "alt")
        #expect(terminal.normalBuffer.yBase == 0)
    }

    @Test func prependDoesNotImportForeignPromptGroupsOrCellTags() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 16, rows: 3, scrollback: 20)
        terminal.feed(text: "live")
        let capture = "\u{1b}]133;A\u{7}> \u{1b}]133;B\u{7}old"
        #expect(terminal.prependScrollbackCapture(byteArray: Array(capture.utf8)[...]) == 1)
        #expect(terminal.buffer.semanticPromptInvariantsHold())
        #expect(terminal.buffer.lines[0].semanticMarks.isEmpty)
        #expect(terminal.buffer.lines[0].semanticHardContinuationGroup == nil)
        for column in 0..<terminal.cols {
            #expect(terminal.buffer.lines[0][column].semanticContent == .none)
        }
        #expect(terminal.buffer.translateBufferLineToString(lineIndex: 0, trimRight: true,
            characterProvider: { terminal.getCharacter(for: $0) }) == "> old")
    }
}

#if os(macOS)
import AppKit

@MainActor
struct Upstream119ClearScrollbackViewTests {
    @Test func clearingHistoryInvalidatesSearchSnapshot() {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 320, height: 100))
        view.resize(cols: 16, rows: 3)
        view.feed(text: "needle\r\n1\r\n2\r\n3\r\n4")
        #expect(view.search.findNext(term: "needle") != nil)
        #expect(view.search.lastResult != nil)
        view.clearScrollback()
        #expect(view.search.lastResult == nil)
        #expect(view.search.findNext(term: "needle") == nil)
    }
}
#endif
