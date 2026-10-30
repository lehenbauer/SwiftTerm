//
//  LineInfoCacheTests.swift
//
//  The fork's CG line-info cache (`47a3079`) is superseded on v1.99.2 by the
//  frame snapshot, which copies a row only when its source line or generation
//  changed, and the snapshot text builder. These tests keep the fork's two
//  observable contracts on that seam: a row's rendering follows its line's
//  generation, and invalidating one row leaves the other rows' copies alone.
//
import Foundation
import Testing

@testable import SwiftTerm

#if os(macOS)
@MainActor
final class LineInfoCacheTests {
    private func refresh(_ snapshot: TerminalSnapshot, _ view: TerminalView) {
        let viewState = FrameViewState(view: view)
        view.withTerminal { terminal in
            _ = snapshot.refresh(terminal: terminal, viewState: viewState,
                                 selection: SnapshotSelectionState(selection: view.selection))
        }
    }

    private func renderedText(_ snapshot: TerminalSnapshot, _ view: TerminalView, row: Int) -> String {
        let context = SnapshotRenderContext(viewState: FrameViewState(view: view), snapshot: snapshot)
        let info = view.textBuilder.buildAttributedString(row: snapshot.rows[row - snapshot.firstRow],
                                                          absoluteRow: row, context: context)
        return info.segments.map { $0.attributedString.string }.joined()
            .trimmingCharacters(in: .whitespaces)
    }

    @Test func testCachedLineInfoTracksBufferLineGeneration() {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        view.resize(cols: 10, rows: 3)
        let snapshot = TerminalSnapshot()

        view.feed(text: "abc")
        refresh(snapshot, view)
        #expect(renderedText(snapshot, view, row: 0) == "abc")

        // Unchanged line: nothing is copied again.
        refresh(snapshot, view)
        #expect(snapshot.rowsCopied == 0)
        #expect(renderedText(snapshot, view, row: 0) == "abc")

        // A new generation of the same line: that row is copied again.
        view.feed(text: "d")
        refresh(snapshot, view)
        #expect(snapshot.rowsCopied == 1)
        #expect(renderedText(snapshot, view, row: 0) == "abcd")
    }

    @Test func testInvalidatingOneLineInfoRowKeepsOtherRows() {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        view.resize(cols: 10, rows: 3)
        let snapshot = TerminalSnapshot()

        view.feed(text: "abc\r\nxyz")
        refresh(snapshot, view)

        // Change only row 0.
        view.feed(text: "\u{1b}[1;4HQ")
        refresh(snapshot, view)

        #expect(snapshot.rowsCopied == 1)
        #expect(snapshot.rowsSkipped == 2)
        #expect(renderedText(snapshot, view, row: 0) == "abcQ")
        #expect(renderedText(snapshot, view, row: 1) == "xyz")
    }
}
#endif
