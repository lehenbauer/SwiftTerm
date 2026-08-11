import Testing
@testable import SwiftTerm

#if os(macOS)
import AppKit

/// Records the rects `updateDisplay` asks AppKit to repaint.
private final class InvalidationCapturingTerminalView: TerminalView {
    var invalidated: [NSRect] = []

    override func setNeedsDisplay(_ invalidRect: NSRect) {
        invalidated.append(invalidRect)
        super.setNeedsDisplay(invalidRect)
    }
}

struct ScrollbackRepaintTests {
    private let esc = "\u{1b}"

    /// The update range is recorded in `buffer.y` space (relative to `yBase`),
    /// but the draw maps screen rects back to buffer rows through `yDisp`. When
    /// the viewport is scrolled back the two disagree by `yBase - yDisp`, so a
    /// partial invalidation lands on the wrong screen rows and the cells that
    /// changed keep stale content.
    ///
    /// Scrolling output hides this, since `scroll()` dirties both `scrollTop`
    /// and `scrollBottom` and the whole view gets invalidated anyway. The case
    /// that stays exposed is an in-place repaint, so the write below neither
    /// scrolls nor moves the cursor between rows.
    @Test func inPlaceRepaintWhileScrolledBackInvalidatesRenderedRow() {
        let view = InvalidationCapturingTerminalView(frame: CGRect(x: 0, y: 0, width: 640, height: 320))
        let terminal: Terminal = view.terminal
        let cellHeight = view.cellDimension.height

        for i in 0..<(terminal.rows * 3) {
            terminal.feed(text: "line \(i)\r\n")
        }
        view.updateDisplay()

        let scrolledBackBy = 3
        let maxScrollback = max(0, terminal.buffer.lines.count - terminal.buffer.rows)
        view.scrollTo(row: maxScrollback - scrolledBackBy)
        #expect(terminal.buffer.yBase - terminal.buffer.yDisp == scrolledBackBy)

        // Park the cursor on the target row and flush, so the repaint below
        // dirties only that row instead of also dirtying the row it came from.
        let targetRow = 2
        terminal.feed(text: "\(esc)[\(targetRow + 1);1H")
        view.updateDisplay()
        terminal.clearUpdateRange()
        view.invalidated.removeAll()

        terminal.feed(text: "XXXX")
        let updateRange = terminal.getUpdateRange()
        #expect(updateRange?.startY == targetRow)
        #expect(updateRange?.endY == targetRow)
        view.updateDisplay()

        // The change is on buffer row `targetRow` of the live screen, which is
        // drawn `yBase - yDisp` rows further down the viewport.
        let renderedRow = targetRow + (terminal.buffer.yBase - terminal.buffer.yDisp)
        let rowBottom = view.frame.height - CGFloat(renderedRow + 1) * cellHeight
        let rowTop = rowBottom + cellHeight
        let repainted = view.invalidated.contains { $0.minY <= rowBottom && $0.maxY >= rowTop }
        #expect(repainted, "invalidated \(view.invalidated), change renders at [\(rowBottom), \(rowTop)]")
    }

    // MARK: - Scrolled-back repaint skip

    /// Builds a view with `pages` screens of scrollback, scrolled to the top,
    /// with the invalidation log and update range cleared and the skip's
    /// tracking state primed by one updateDisplay pass.
    private func makeDeepScrolledBackView(pages: Int = 3) -> (InvalidationCapturingTerminalView, Terminal) {
        let view = InvalidationCapturingTerminalView(frame: CGRect(x: 0, y: 0, width: 640, height: 320))
        let terminal: Terminal = view.terminal
        for i in 0..<(terminal.rows * pages) {
            terminal.feed(text: "line \(i)\r\n")
        }
        view.updateDisplay()
        view.scrollTo(row: 0)
        #expect(terminal.buffer.yBase - terminal.buffer.yDisp >= terminal.rows)
        view.updateDisplay()
        terminal.clearUpdateRange()
        view.invalidated.removeAll()
        return (view, terminal)
    }

    private func fullFrameInvalidated(_ view: InvalidationCapturingTerminalView) -> Bool {
        view.invalidated.contains { $0.width >= view.frame.width && $0.height >= view.frame.height }
    }

    @Test func deepScrollbackInPlaceWriteSkipsInvalidation() {
        let (view, terminal) = makeDeepScrolledBackView()
        terminal.feed(text: "XXXX")
        view.updateDisplay()
        #expect(view.invalidated.isEmpty, "invalidated \(view.invalidated)")
    }

    @Test func deepScrollbackScrollingOutputSkipsInvalidation() {
        let (view, terminal) = makeDeepScrolledBackView()
        for i in 0..<5 {
            terminal.feed(text: "more \(i)\r\n")
            view.updateDisplay()
        }
        #expect(view.invalidated.isEmpty, "invalidated \(view.invalidated)")
    }

    @Test func capacitySlideCompensatedKeepsSkipping() {
        let view = InvalidationCapturingTerminalView(frame: CGRect(x: 0, y: 0, width: 640, height: 320))
        let terminal: Terminal = view.terminal
        // Shrink scrollback so the buffer reaches capacity quickly, then fill it.
        view.changeScrollback(terminal.rows * 2)
        for i in 0..<(terminal.rows * 4) {
            terminal.feed(text: "line \(i)\r\n")
        }
        #expect(terminal.buffer.lines.isFull)
        // Scroll deep but leave yDisp > 0 headroom so recycle compensation
        // (linesTop += 1, yDisp -= 1) has room to keep the content stable.
        view.scrollTo(row: 2)
        let buffer = terminal.buffer
        #expect(buffer.yDisp == 2)
        #expect(buffer.yBase - buffer.yDisp >= terminal.rows)
        view.updateDisplay()
        terminal.clearUpdateRange()
        view.invalidated.removeAll()

        terminal.feed(text: "slide 1\r\n")
        view.updateDisplay()
        #expect(buffer.yDisp == 1, "recycle should compensate yDisp")
        #expect(view.invalidated.isEmpty, "invalidated \(view.invalidated)")
    }

    @Test func capacitySlideAtTopForcesRepaint() {
        let view = InvalidationCapturingTerminalView(frame: CGRect(x: 0, y: 0, width: 640, height: 320))
        let terminal: Terminal = view.terminal
        view.changeScrollback(terminal.rows * 2)
        for i in 0..<(terminal.rows * 4) {
            terminal.feed(text: "line \(i)\r\n")
        }
        #expect(terminal.buffer.lines.isFull)
        view.scrollTo(row: 0)
        view.updateDisplay()
        terminal.clearUpdateRange()
        view.invalidated.removeAll()

        // yDisp is pinned at 0: the head drop cannot be compensated, so the
        // content under the viewport slides and must repaint.
        terminal.feed(text: "slide\r\n")
        view.updateDisplay()
        #expect(terminal.buffer.yDisp == 0)
        #expect(fullFrameInvalidated(view), "invalidated \(view.invalidated)")
    }

    @Test func paletteChangeWhileScrolledBackForcesRepaint() {
        let (view, _) = makeDeepScrolledBackView()
        view.installColors(Array(repeating: Color(red: 0, green: 0, blue: 0), count: 16))
        view.updateDisplay()
        #expect(fullFrameInvalidated(view), "invalidated \(view.invalidated)")
    }

    @Test func altScreenRoundTripWhileScrolledBackForcesRepaint() {
        let (view, terminal) = makeDeepScrolledBackView()
        // Enter the alternate screen (pinned path paints it), then leave it:
        // the normal buffer is still scrolled back, its content and anchor are
        // unchanged, and only live rows are marked — yet the pixels on screen
        // are the alt frame, so the exit tick must repaint.
        terminal.feed(text: "\(esc)[?1049h")
        view.updateDisplay()
        view.invalidated.removeAll()
        terminal.feed(text: "\(esc)[?1049l")
        #expect(terminal.buffer.yDisp != terminal.buffer.yBase)
        view.updateDisplay()
        #expect(fullFrameInvalidated(view), "invalidated \(view.invalidated)")
    }

    @Test func shrinkScrollbackWhileScrolledBackForcesRepaint() {
        let (view, terminal) = makeDeepScrolledBackView(pages: 4)
        view.scrollTo(row: 4)
        view.updateDisplay()
        terminal.clearUpdateRange()
        view.invalidated.removeAll()

        view.changeScrollback(terminal.rows)
        view.updateDisplay()
        #expect(fullFrameInvalidated(view), "invalidated \(view.invalidated)")
    }

    @Test func insertLinesWhileScrolledBackForcesRepaint() {
        let (view, terminal) = makeDeepScrolledBackView()
        // ILM records absolute buffer indices in the update range; the skip
        // must treat out-of-live-space marks as untranslatable and repaint.
        terminal.feed(text: "\(esc)[2;1H\(esc)[2L")
        view.updateDisplay()
        #expect(fullFrameInvalidated(view), "invalidated \(view.invalidated)")
    }

    @Test func preservingResizeWhileScrolledBackForcesRepaint() {
        let (view, terminal) = makeDeepScrolledBackView()
        // Column changes reflow history under the viewport; Terminal.resize
        // bumps fullRefreshGeneration so the skip repaints.
        view.resize(cols: terminal.cols - 4, rows: terminal.rows, preservingTerminalModes: true)
        #expect(terminal.buffer.yDisp != terminal.buffer.yBase)
        view.updateDisplay()
        #expect(fullFrameInvalidated(view), "invalidated \(view.invalidated)")
    }

    @Test func prependWhileScrolledBackSkipsInvalidation() {
        let (view, terminal) = makeDeepScrolledBackView()
        let before = terminal.buffer.yDisp
        let inserted = view.prependScrollbackCapture(byteArray: ArraySlice("old 1\r\nold 2\r\n".utf8))
        #expect(inserted > 0)
        // Prepending compensates linesTop/yDisp so the viewport shows the same
        // content; nothing visible changed and nothing should repaint.
        #expect(terminal.buffer.yDisp == before + inserted)
        view.updateDisplay()
        #expect(view.invalidated.isEmpty, "invalidated \(view.invalidated)")
    }

    @Test func hoverInvalidationWhileScrolledBackHitsViewportRow() {
        let (view, terminal) = makeDeepScrolledBackView()
        let cellHeight = view.cellDimension.height
        let screenRow = 2
        view.invalidateLinkHighlightRow(terminal.buffer.yDisp + screenRow)
        // The CG path invalidates the viewport row directly (extended one cell
        // down) and must not route through the live-space update range.
        #expect(terminal.getUpdateRange() == nil)
        let rowBottom = view.frame.height - CGFloat(screenRow + 1) * cellHeight
        let rowTop = rowBottom + cellHeight
        let repainted = view.invalidated.contains { $0.minY <= rowBottom && $0.maxY >= rowTop }
        #expect(repainted, "invalidated \(view.invalidated), row band [\(rowBottom), \(rowTop)]")
    }
}
#endif
