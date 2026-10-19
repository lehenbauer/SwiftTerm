import Testing
@testable import SwiftTerm

struct ScrollbackHydrationTests {
    // Compare resolved characters, not terminal-local compound-character codes.
    // OSC 8 target lifetime is a separate known defect; only payload presence
    // and rendering compatibility are covered here.
    private struct Cell: Equatable {
        let character: Character
        let width: Int8
        let attribute: Attribute
        let hasPayload: Bool
    }

    private struct Row: Equatable {
        let cells: [Cell]
        let wrapped: Bool
    }

    private func snapshot(_ terminal: Terminal, start: Int = 0, count: Int) -> [Row] {
        (start..<(start + count)).map { index in
            let line = terminal.buffer.lines[index]
            return Row(cells: (0..<terminal.cols).map { column in
                let cell = line[column]
                return Cell(character: terminal.getCharacter(for: cell), width: cell.width,
                            attribute: cell.attribute, hasPayload: cell.hasPayload)
            }, wrapped: line.isWrapped)
        }
    }

    /// Ordinary feed with a spacious, multi-row viewport is independent of
    /// prepend's scratch storage and extraction. Captures are sequential text,
    /// rendition and charset data, rather than arbitrary cursor controls.
    @discardableResult
    private func checkCapture(_ capture: String, capacity: Int = 100,
                              options: TerminalOptions = TerminalOptions(cols: 8)) -> Int {
        let delegate = TerminalTestDelegate()
        var referenceOptions = options
        referenceOptions.rows = 17
        referenceOptions.scrollback = 10_000
        let reference = Terminal(delegate: delegate, options: referenceOptions)
        // Start on the bottom row so continuation rows are created by normal
        // scrolling with the current erase background, rather than using the
        // viewport's initially blank rows (which predate any captured SGR).
        reference.feed(text: "\u{1b}[17;1H")
        reference.feed(text: capture)
        let physicalCount = reference.buffer.yBase + reference.buffer.y + 1 - 16
        #expect(reference.buffer.totalLinesTrimmed == 0)
        let expected = snapshot(reference, start: 16, count: physicalCount)

        var liveOptions = options
        liveOptions.rows = 3
        liveOptions.scrollback = capacity
        let terminal = Terminal(delegate: delegate, options: liveOptions)
        terminal.feed(text: "LIVE\r\nKEEP")
        terminal.feed(text: "\u{1b}7")
        let buffer = terminal.buffer
        let visible = snapshot(terminal, start: buffer.yDisp, count: terminal.rows)
        let identities = (0..<buffer.lines.count).map { buffer.lines[$0] }
        let oldX = buffer.x, oldY = buffer.y
        let savedX = buffer.savedX, savedY = buffer.savedY
        let oldBase = buffer.yBase, oldDisp = buffer.yDisp, oldTop = buffer.linesTop
        let selection = SelectionService(terminal: terminal)
        selection.setSelection(start: Position(col: 0, row: 0), end: Position(col: 4, row: 0))
        let selected = selection.getSelectedText()
        let inserted = terminal.prependScrollbackCapture(byteArray: Array(capture.utf8)[...])
        #expect(inserted == min(capacity, physicalCount))
        // Boolean comparison also keeps large stress-test failures bounded.
        let cellsMatch = snapshot(terminal, count: inserted) == Array(expected.suffix(capacity))
        #expect(cellsMatch)
        #expect(snapshot(terminal, start: buffer.yDisp, count: terminal.rows) == visible)
        #expect(identities.indices.allSatisfy { buffer.lines[inserted + $0] === identities[$0] })
        #expect(buffer.lines.count == identities.count + inserted)
        #expect(buffer.lines.count <= buffer.lines.maxLength)
        #expect(buffer.linesTop == oldTop - inserted)
        #expect(buffer.yBase == oldBase + inserted)
        #expect(buffer.yDisp == oldDisp + inserted)
        #expect(buffer.x == oldX && buffer.y == oldY)
        #expect(buffer.savedX == savedX && buffer.savedY == savedY)
        #expect(selection.active && selection.getSelectedText() == selected)
        #expect(selection.start.row == inserted && selection.end.row == inserted)
        for row in 0..<inserted {
            for column in 0..<terminal.cols {
                #expect(buffer.lines[row][column].semanticContent == .none)
            }
        }
        withExtendedLifetime((delegate, selection)) {}
        return inserted
    }

    @Test(arguments: [
        "FIRST-abcdefghijklmnop\r\nSECOND-abcdefghijklmnop\r\nend",
        "12345678abcdefgh\r\nnext", // two exact-width rows, then a hard line
        "12345678", "12345678\r\n", // deferred wrap and final blank
        "1234567界tail界界end", // wide cell at the right edge
        String(repeating: "e\u{301}", count: 25),
        "\u{1b}[1;38;2;12;34;56;48;5;42;4:3mabcdefghijklmnopq\u{1b}[0mend",
        "\u{1b}]8;;https://example.invalid/\u{1b}\\abcdefghijklmnopq\u{1b}]8;;\u{1b}\\end",
        "\u{1b}(0lqqqqqqqqqqk\u{1b}(B\r\nend"
    ])
    func physicalRowsAndCellsMatchOrdinaryFeed(capture: String) {
        checkCapture(capture)
    }

    @Test(arguments: ["short", "one\r\ntwo", "one\r\ntwo\r\n", "\r\n\r\n", "one\n\ntwo\n"])
    func nonwrappingAndBlankControls(capture: String) {
        checkCapture(capture)
    }

    @Test(arguments: [0, 1, 2, 3, 4, 10])
    func capacityRetainsPhysicalSuffix(capacity: Int) {
        // Four physical rows; style starts in a row discarded at capacity 1–3.
        checkCapture("\u{1b}[31;1mabcdefghijklmnopqrstuvwxy\u{1b}[0m", capacity: capacity)
    }

    @Test func inheritsRegionalIndicatorWidth() {
        var options = TerminalOptions(cols: 8)
        options.regionalIndicatorWidth = .narrow
        checkCapture(String(repeating: "🇺🇸", count: 12), options: options)
    }

    @Test func inheritsTabStops() {
        var options = TerminalOptions(cols: 16)
        options.tabStopWidth = 4
        checkCapture("a\tb\tc\td\te", options: options)
    }

    @Test func inheritsBareLinefeedConversion() {
        var options = TerminalOptions(cols: 8)
        options.convertEol = true
        checkCapture("first\nsecond\nthird", options: options)
    }

    @Test func largeJoinedCaptureWithTinyCapacity() {
        // Scratch storage must remain bounded even for a single huge logical
        // line. The production scratch-capacity assertions execute in this run.
        checkCapture(String(repeating: "abcdefgh", count: 10_000), capacity: 2)
    }

    @Test func repeatedPrependPreservesParkedViewportAndSelection() {
        let (terminal, delegate) = TerminalTestHarness.makeTerminal(cols: 8, rows: 3, scrollback: 100)
        terminal.feed(text: "LIVE\r\nKEEP\r\nLAST\r\nTAIL")
        terminal.buffer.yDisp = 0
        terminal.userScrolling = true
        let visible = snapshot(terminal, count: 3)
        let anchor = terminal.buffer.linesTop + terminal.buffer.yDisp
        let selection = SelectionService(terminal: terminal)
        selection.setSelection(start: Position(col: 0, row: 0), end: Position(col: 4, row: 0))
        let selected = selection.getSelectedText()
        let newer = terminal.prependScrollbackCapture(byteArray: Array("NEWER-abcdefghijkl".utf8)[...])
        let newerRows = snapshot(terminal, count: newer)
        let older = terminal.prependScrollbackCapture(byteArray: Array("OLDER-abcdefghijkl".utf8)[...])
        #expect(newer == 3 && older == 3)
        #expect(snapshot(terminal, start: older, count: newer) == newerRows)
        #expect(snapshot(terminal, start: terminal.buffer.yDisp, count: 3) == visible)
        #expect(terminal.buffer.linesTop + terminal.buffer.yDisp == anchor)
        #expect(terminal.userScrolling)
        #expect(selection.active && selection.getSelectedText() == selected)
        #expect(selection.start.row == newer + older)
        withExtendedLifetime((delegate, selection)) {}
    }

    @Test func truncatedContinuationSurvivesReflow() {
        let (terminal, delegate) = TerminalTestHarness.makeTerminal(cols: 8, rows: 3, scrollback: 2)
        terminal.feed(text: "LIVE")
        let inserted = terminal.prependScrollbackCapture(byteArray: Array("abcdefghijklmnopqrstuvwxy".utf8)[...])
        #expect(inserted == 2)
        #expect(terminal.buffer.lines[0].isWrapped)
        for cols in [7, 10, 8] {
            terminal.resize(cols: cols, rows: 3)
            #expect(terminal.buffer.lines.count <= terminal.buffer.lines.maxLength)
            let allText = (0..<terminal.buffer.lines.count).map {
                terminal.buffer.translateBufferLineToString(lineIndex: $0, trimRight: true,
                    characterProvider: { terminal.getCharacter(for: $0) })
            }.joined()
            #expect(allText.contains("LIVE"))
        }
        withExtendedLifetime(delegate) {}
    }

    @Test func emptyAlternateAndFullCapacityAreNoOps() {
        let (terminal, delegate) = TerminalTestHarness.makeTerminal(cols: 8, rows: 3, scrollback: 0)
        terminal.feed(text: "LIVE")
        let before = snapshot(terminal, count: 3)
        #expect(terminal.prependScrollbackCapture(byteArray: []) == 0)
        #expect(terminal.prependScrollbackCapture(byteArray: Array("older".utf8)[...]) == 0)
        #expect(snapshot(terminal, count: 3) == before)
        terminal.feed(text: "\u{1b}[?1049h")
        let alternate = snapshot(terminal, count: 3)
        #expect(terminal.prependScrollbackCapture(byteArray: Array("older".utf8)[...], maximumScrollback: 100) == 0)
        #expect(snapshot(terminal, count: 3) == alternate)
        withExtendedLifetime(delegate) {}
    }

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
