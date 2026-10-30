//
//  MirrorSemanticPromptTests.swift
//
//  `ignoreSemanticPromptsForTmuxMirror()` makes OSC 133 a parser no-op for a
//  view that mirrors another emulator's grid: no fresh line, no prompt marks,
//  and the override survives RIS. A control view keeps upstream handling.
//
#if os(macOS)
import AppKit
import Testing
@testable import SwiftTerm

@MainActor
struct MirrorSemanticPromptTests {
    private let esc = "\u{1b}"

    private func makeView(ignoringPrompts: Bool) -> TerminalView {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 200), font: nil,
                                terminalOptions: TerminalOptions(cols: 40, rows: 6),
                                initialGeometry: .grid(cols: 40, rows: 6), autoResizeGrid: false)
        if ignoringPrompts {
            view.ignoreSemanticPromptsForTmuxMirror()
        }
        return view
    }

    private func cursor(_ view: TerminalView) -> Position {
        view.terminalStateSnapshot().cursor
    }

    private func feedPromptMarks(_ view: TerminalView) {
        for mark in ["A", "N", "L"] {
            view.feed(text: "abc\(esc)]133;\(mark)\u{07}")
        }
        view.feed(text: "\(esc)]133;B\u{07}cmd\(esc)]133;C\u{07}")
    }

    @Test func controlViewMovesPromptToFreshLine() {
        let view = makeView(ignoringPrompts: false)
        view.feed(text: "abc\(esc)]133;A\u{07}")
        // Upstream OSC 133;A at a nonzero column starts a fresh line.
        #expect(cursor(view) == Position(col: 0, row: 1))
    }

    @Test func mirrorIgnoresPromptMarksAtNonzeroColumn() {
        let view = makeView(ignoringPrompts: true)
        feedPromptMarks(view)
        #expect(cursor(view) == Position(col: 12, row: 0))
        #expect(view.visibleRowsText(0..<1) == ["abcabcabccmd"])
        #expect(view.previousSemanticPromptRow() == nil)
        #expect(view.nextSemanticPromptRow() == nil)
    }

    @Test func mirrorIgnoresPromptMarksAfterFullReset() {
        let view = makeView(ignoringPrompts: true)
        view.feed(text: "\(esc)c")
        feedPromptMarks(view)
        #expect(cursor(view) == Position(col: 12, row: 0))
        #expect(view.previousSemanticPromptRow() == nil)
        view.softReset()
        view.feed(text: "\r\nxy\(esc)]133;A\u{07}")
        #expect(cursor(view) == Position(col: 2, row: 1))
    }
}
#endif
