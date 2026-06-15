import Testing
@testable import SwiftTerm

struct ScrollbackHydrationTests {
    @Test func prependingScrollbackPreservesVisibleRows() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 16, rows: 3, scrollback: 10)
        terminal.feed(text: "visible one\r\nvisible two")

        let before = TerminalTestHarness.visibleLinesText(buffer: terminal.buffer, terminal: terminal)
        let inserted = terminal.prependScrollbackCapture(
            byteArray: Array("old one\r\nold two".utf8)[...],
            maximumScrollback: 10
        )
        let after = TerminalTestHarness.visibleLinesText(buffer: terminal.buffer, terminal: terminal)

        #expect(inserted == 2)
        #expect(after == before)
        #expect(terminal.buffer.yDisp == 2)
        #expect(terminal.buffer.totalLinesTrimmed == -2)
        #expect(terminal.buffer.lines.count == 5)
        #expect(terminal.buffer.translateBufferLineToString(lineIndex: 0, trimRight: true, characterProvider: { terminal.getCharacter(for: $0) }) == "old one")
        #expect(terminal.buffer.translateBufferLineToString(lineIndex: 1, trimRight: true, characterProvider: { terminal.getCharacter(for: $0) }) == "old two")
    }

    @Test func prependingScrollbackKeepsRowsNearestAnchorWhenCapacityIsLimited() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 16, rows: 2, scrollback: 1)
        terminal.feed(text: "visible")

        let inserted = terminal.prependScrollbackCapture(
            byteArray: Array("too old\r\nnear anchor".utf8)[...],
            maximumScrollback: 1
        )

        #expect(inserted == 1)
        #expect(terminal.buffer.lines.count == 3)
        #expect(terminal.buffer.translateBufferLineToString(lineIndex: 0, trimRight: true, characterProvider: { terminal.getCharacter(for: $0) }) == "near anchor")
    }
}
