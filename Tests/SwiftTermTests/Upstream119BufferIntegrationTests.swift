import Testing
@testable import SwiftTerm

// ImageTests' mock is macOS-only; the buffer tests also run on iOS.
private struct ClearHistoryTestImage: TerminalImage {
    var pixelWidth = 1
    var pixelHeight = 1
    var col = 0
}

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

    // DECSC stores a screen row. Clearing history leaves the screen (and the
    // cursor) where they were, so the saved row must not move either.
    @Test func clearingHistoryKeepsSavedCursorOnItsScreenRow() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 16, rows: 3, scrollback: 20)
        for i in 0..<8 { terminal.feed(text: "row \(i)\r\n") }
        terminal.feed(text: "\u{1b}[2;4H\u{1b}7\u{1b}[1;1H")
        #expect(terminal.buffer.yBase > 1)
        terminal.clearScrollback()
        terminal.feed(text: "\u{1b}8")
        TerminalTestHarness.assertCursor(terminal.buffer, col: 3, row: 1)
    }

    @Test func clearingHistoryUnderAlternateScreenKeepsNormalSavedCursor() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 16, rows: 3, scrollback: 20)
        for i in 0..<8 { terminal.feed(text: "row \(i)\r\n") }
        terminal.feed(text: "\u{1b}[2;4H\u{1b}[?1049h\u{1b}[3;1Halt")
        let normalScreen = TerminalTestHarness.visibleLinesText(buffer: terminal.normalBuffer, terminal: terminal)
        terminal.clearScrollback()
        #expect(terminal.isCurrentBufferAlternate)
        TerminalTestHarness.assertLineText(terminal.buffer, terminal: terminal, row: 2, equals: "alt")
        terminal.feed(text: "\u{1b}[?1049l")
        #expect(!terminal.isCurrentBufferAlternate)
        #expect(TerminalTestHarness.visibleLinesText(buffer: terminal.buffer, terminal: terminal) == normalScreen)
        TerminalTestHarness.assertCursor(terminal.buffer, col: 3, row: 1)
    }

    @Test func clearingHistoryForgetsImagesOnlyOnTrimmedRows() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 16, rows: 3, scrollback: 20)
        for i in 0..<8 { terminal.feed(text: "row \(i)\r\n") }
        let buffer = terminal.buffer
        buffer.attachImage(ClearHistoryTestImage(), toLineAt: 0)
        buffer.attachImage(ClearHistoryTestImage(), toLineAt: 1)
        #expect(buffer.hasAnyImages)
        terminal.clearScrollback()
        #expect(!buffer.hasAnyImages, "only trimmed history rows carried images")

        for i in 0..<8 { terminal.feed(text: "more \(i)\r\n") }
        buffer.attachImage(ClearHistoryTestImage(), toLineAt: 0)
        buffer.attachImage(ClearHistoryTestImage(), toLineAt: buffer.yBase)
        terminal.clearScrollback()
        #expect(buffer.hasAnyImages, "the retained live row still carries an image")
        buffer.clearImagesFromLine(at: 0)
        #expect(!buffer.hasAnyImages, "exactly one retained image row remains counted")
    }

    // A viewport parked in history is inside the scrollback that clearing
    // removes; it lands on the live screen and must follow later output.
    @Test func clearingHistoryWhileScrolledBackResumesFollowingOutput() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 16, rows: 3, scrollback: 20)
        for i in 0..<8 { terminal.feed(text: "row \(i)\r\n") }
        terminal.setViewYDisp(1)
        terminal.userScrolling = true
        terminal.clearScrollback()
        #expect(terminal.buffer.yDisp == terminal.buffer.yBase)
        #expect(!terminal.userScrolling)
        for i in 0..<5 { terminal.feed(text: "out \(i)\r\n") }
        #expect(terminal.buffer.yBase > 0)
        #expect(terminal.buffer.yDisp == terminal.buffer.yBase)
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

    @Test func clearingHistoryWhileScrolledBackResumesFollowingOutput() {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 320, height: 100))
        view.resize(cols: 16, rows: 3)
        view.getTerminal().changeScrollback(20)
        view.feed(text: (0..<10).map { "row \($0)" }.joined(separator: "\r\n"))
        let terminal = view.getTerminal()
        let liveScreen = TerminalTestHarness.visibleLinesText(buffer: terminal.buffer, terminal: terminal)
        view.scrollUp(lines: 2)
        #expect(view.userScrolling && terminal.userScrolling)
        view.clearScrollback()
        #expect(!view.userScrolling)
        #expect(!terminal.userScrolling)
        #expect(terminal.buffer.yDisp == terminal.buffer.yBase)
        #expect(TerminalTestHarness.visibleLinesText(buffer: terminal.buffer, terminal: terminal) == liveScreen)
        view.feed(text: (0..<5).map { "\r\nout \($0)" }.joined())
        #expect(terminal.buffer.yBase > 0)
        #expect(terminal.buffer.yDisp == terminal.buffer.yBase)
    }
}
#endif

#if os(iOS) || os(visionOS)
import UIKit

@MainActor
struct Upstream119ClearScrollbackIOSTests {
    private final class DragView: TerminalView {
        var simulatedTracking = false
        override var isTracking: Bool { simulatedTracking }
    }

    // A drag that parks mid-row records a sub-row offset. Clearing history
    // resumes following, so neither the flag nor that fraction may survive to
    // lift the bottom-pinned offset once output grows the content again.
    @Test func clearingHistoryAfterFractionalDragResumesFollowingAtBottom() {
        let view = DragView(
            frame: CGRect(x: 0, y: 0, width: 464, height: 700), font: nil,
            terminalOptions: TerminalOptions(cols: 58, rows: 50, scrollback: 2_000),
            initialGeometry: .grid(cols: 58, rows: 50), autoResizeGrid: false
        )
        view.contentInsetAdjustmentBehavior = .never
        let cellHeight = view.cellDimension.height
        view.frame.size.height = 50 * cellHeight
        let terminal = view.getTerminal()
        terminal.feed(text: (0..<150).map { "existing \($0)" }.joined(separator: "\r\n"))
        view.updateScroller()

        view.simulatedTracking = true
        view.scrollViewWillBeginDragging(view)
        view.contentOffset.y = 46.4 * cellHeight
        view.scrollViewDidScroll(view)
        view.simulatedTracking = false
        view.scrollViewDidEndDragging(view, willDecelerate: false)
        #expect(view.userScrolling && terminal.userScrolling)
        #expect(terminal.buffer.yDisp == 46)

        view.clearScrollback()
        #expect(!view.userScrolling)
        #expect(!terminal.userScrolling)
        #expect(terminal.buffer.yDisp == terminal.buffer.yBase)

        terminal.feed(text: (0..<60).map { "\r\nout \($0)" }.joined())
        view.updateScroller()
        #expect(terminal.buffer.yBase == 60)
        #expect(terminal.buffer.yDisp == terminal.buffer.yBase)
        #expect(abs(view.contentOffset.y - CGFloat(terminal.buffer.yDisp) * cellHeight) < 0.01,
                "offset \(view.contentOffset.y) vs bottom row \(CGFloat(terminal.buffer.yDisp) * cellHeight)")
    }
}
#endif
