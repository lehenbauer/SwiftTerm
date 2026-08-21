#if os(macOS)
import Foundation
import Testing
@testable import SwiftTerm

@MainActor
final class StyledSelectionTests {
    private let esc = "\u{1b}"

    private func makeView (cols: Int = 80, rows: Int = 5) -> TerminalView {
        let view = TerminalView(frame: CGRect(origin: .zero, size: CGSize(width: 640, height: 160)))
        view.resize(cols: cols, rows: rows)
        return view
    }

    private func selectAll(_ view: TerminalView) {
        view.selectAll()
    }

    private func select(_ view: TerminalView, start: Position, end: Position) {
        view.selection.setSelection(start: start, end: end)
    }

    private func expectConcatenationMatchesPlainSelection(_ view: TerminalView) {
        guard let runs = view.getSelectedStyledRuns(), let plain = view.getSelection() else {
            Issue.record("expected an active selection with styled runs")
            return
        }
        #expect(runs.map(\.text).joined() == plain)
    }

    private func expectSingleStyledRun(_ view: TerminalView, style: CharacterStyle) {
        guard let runs = view.getSelectedStyledRuns() else {
            Issue.record("expected an active selection")
            return
        }
        #expect(runs.count == 1)
        #expect(runs.first?.text == "X")
        #expect(runs.first?.style == style)
    }

    @Test func testSelectedStyledRunsExposeStylesAndMidLineReset() {
        let view = makeView()
        let source = "\(esc)[1mBOLD\(esc)[22m plain \(esc)[3mITALIC\(esc)[23m \(esc)[4mUNDER\(esc)[24m \(esc)[9mSTRIKE\(esc)[29m"
        let displayText = "BOLD plain ITALIC UNDER STRIKE"
        view.feed(text: source)
        select(view, start: Position(col: 0, row: 0), end: Position(col: displayText.count, row: 0))

        guard let runs = view.getSelectedStyledRuns() else {
            Issue.record("expected an active selection")
            return
        }
        #expect(runs.map(\.text).joined() == view.getSelection())
        #expect(runs.contains { $0.text == "BOLD" && $0.style == .bold })
        #expect(runs.contains { $0.text == "ITALIC" && $0.style == .italic })
        #expect(runs.contains { $0.text == "UNDER" && $0.style == .underline })
        #expect(runs.contains { $0.text == "STRIKE" && $0.style == .crossedOut })
        #expect(runs.contains { $0.text == " plain " && $0.style == .none })
    }

    @Test func testCurlyUnderlineDowngradesToUnderlinePresence() {
        let view = makeView()
        view.feed(text: "\(esc)[4:3mX")
        select(view, start: Position(col: 0, row: 0), end: Position(col: 1, row: 0))
        expectSingleStyledRun(view, style: .underline)
    }

    @Test func testDoubleUnderlineDowngradesToUnderlinePresence() {
        let view = makeView()
        view.feed(text: "\(esc)[4:2mX")
        select(view, start: Position(col: 0, row: 0), end: Position(col: 1, row: 0))
        expectSingleStyledRun(view, style: .underline)
    }

    @Test func testDottedUnderlineDowngradesToUnderlinePresence() {
        let view = makeView()
        view.feed(text: "\(esc)[4:4mX")
        select(view, start: Position(col: 0, row: 0), end: Position(col: 1, row: 0))
        expectSingleStyledRun(view, style: .underline)
    }

    @Test func testDashedUnderlineDowngradesToUnderlinePresence() {
        let view = makeView()
        view.feed(text: "\(esc)[4:5mX")
        select(view, start: Position(col: 0, row: 0), end: Position(col: 1, row: 0))
        expectSingleStyledRun(view, style: .underline)
    }

    @Test func testSgr21DoubleUnderlineDowngradesToUnderlinePresence() {
        let view = makeView()
        view.feed(text: "\(esc)[21mX")
        select(view, start: Position(col: 0, row: 0), end: Position(col: 1, row: 0))
        expectSingleStyledRun(view, style: .underline)
    }

    @Test func testRunConcatMatchesAutowrapSelection() {
        let view = makeView(cols: 10)
        view.feed(text: "\(esc)[1mABCDEFGHIJKLMNO\(esc)[22m\r\nsecond")
        select(view, start: Position(col: 0, row: 0), end: Position(col: 6, row: 2))
        expectConcatenationMatchesPlainSelection(view)
        #expect(view.getSelection() == "ABCDEFGHIJKLMNO\nsecond")
        guard let runs = view.getSelectedStyledRuns() else {
            Issue.record("expected an active selection")
            return
        }
        let newlineRuns = runs.filter { $0.text.contains("\n") }
        #expect(!newlineRuns.isEmpty)
        #expect(newlineRuns.allSatisfy { $0.style == .none })
    }

    @Test func testRunConcatMatchesScrollbackSelection() {
        let view = makeView(cols: 10, rows: 2)
        view.getTerminal().changeHistorySize(50)
        view.feed(text: "ABCDEFGHIJKLMNO\r\nsecond\r\nthird\r\nfourth")
        selectAll(view)
        expectConcatenationMatchesPlainSelection(view)
        #expect(view.getSelection()?.contains("ABCDEFGHIJKLMNO") == true)
        #expect(view.getSelection()?.contains("ABCDEFGHIJ\nKLMNO") == false)
    }

    @Test func testRunConcatMatchesWideCharacterAndMidWideSelectionEnd() {
        let view = makeView()
        view.feed(text: "A界B😀C")
        // The endpoint falls on the second cell of the emoji.  The continuation
        // cell is skipped exactly as it is by plain selection extraction.
        select(view, start: Position(col: 0, row: 0), end: Position(col: 5, row: 0))
        expectConcatenationMatchesPlainSelection(view)
        #expect(view.getSelection() == "A界B😀")
    }

    @Test func testRunConcatMatchesBlankGroupsAndTrailingSpaces() {
        let view = makeView(cols: 20, rows: 6)
        view.feed(text: "one\r\n\r\n\r\ntwo")
        select(view, start: Position(col: 0, row: 0), end: Position(col: 3, row: 4))
        expectConcatenationMatchesPlainSelection(view)
        #expect(view.getSelection() == "one\n\n\ntwo")

        let trailing = makeView(cols: 12)
        trailing.feed(text: "text   ")
        select(trailing, start: Position(col: 0, row: 0), end: Position(col: 10, row: 0))
        expectConcatenationMatchesPlainSelection(trailing)
        #expect(trailing.getSelection() == "text   ")
    }

    @Test func testRunConcatMatchesInteriorNulAndAttributeOnlyCells() {
        let view = makeView(cols: 10)
        view.feed(text: "AXB")
        let terminal = view.getTerminal()
        terminal.buffer.lines[0][1] = CharData(attribute: Attribute(fg: .defaultColor, bg: .defaultInvertedColor, style: .bold))
        select(view, start: Position(col: 0, row: 0), end: Position(col: 3, row: 0))
        expectConcatenationMatchesPlainSelection(view)
        #expect(view.getSelection() == "A B")
        #expect(view.getSelectedStyledRuns() == [StyledTextRun(text: "A B", style: .none)])

        let attributeOnly = makeView(cols: 10)
        attributeOnly.feed(text: "A")
        attributeOnly.getTerminal().buffer.lines[0][1] = CharData(attribute: Attribute(fg: .defaultColor, bg: .defaultInvertedColor, style: .bold))
        select(attributeOnly, start: Position(col: 0, row: 0), end: Position(col: 3, row: 0))
        expectConcatenationMatchesPlainSelection(attributeOnly)
        #expect(attributeOnly.getSelection() == "A")
    }

    @Test func testStyledRunsReturnNilWithoutActiveSelection() {
        let view = makeView()
        #expect(view.getSelectedStyledRuns() == nil)
    }

    @Test func testOversizedSelectionStillHasRunConcatInvariant() {
        let view = makeView(cols: 200, rows: 6000)
        view.feed(text: String(repeating: "x", count: 1_100_000))
        selectAll(view)
        expectConcatenationMatchesPlainSelection(view)
    }
}
#endif
