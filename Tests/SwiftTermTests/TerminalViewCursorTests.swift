import Foundation
import Testing

@testable import SwiftTerm

#if os(macOS)
final class TerminalViewCursorTests {
    @Test func testCaretDrawsPendingWrapAtLastVisibleColumn() {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 120, height: 80))
        view.resize(cols: 5, rows: 3)

        let terminal = view.getTerminal()
        terminal.feed(text: "12345")

        #expect(terminal.buffer.x == 5)
        view.updateCursorPosition()

        let expectedX = view.cellDimension.width * 4
        #expect(abs(view.caretFrame.origin.x - expectedX) < 0.001)
    }

    @Test func testMetalBlinkFrameDoesNotHideInactiveCursor() {
        #expect(MetalTerminalRenderer.shouldHideCursorForBlinkFrame(
            style: .blinkBlock,
            hasFocus: false,
            cursorBlinkOn: false,
            cursorActivityVisible: false
        ) == false)
        #expect(MetalTerminalRenderer.shouldHideCursorForBlinkFrame(
            style: .blinkUnderline,
            hasFocus: false,
            cursorBlinkOn: false,
            cursorActivityVisible: false
        ) == false)
        #expect(MetalTerminalRenderer.shouldHideCursorForBlinkFrame(
            style: .blinkBar,
            hasFocus: false,
            cursorBlinkOn: false,
            cursorActivityVisible: false
        ) == false)
    }

    @Test func testMetalBlinkFrameStillHidesFocusedBlinkingCursor() {
        #expect(MetalTerminalRenderer.shouldHideCursorForBlinkFrame(
            style: .blinkBlock,
            hasFocus: true,
            cursorBlinkOn: false,
            cursorActivityVisible: false
        ) == true)
        #expect(MetalTerminalRenderer.shouldHideCursorForBlinkFrame(
            style: .steadyBlock,
            hasFocus: true,
            cursorBlinkOn: false,
            cursorActivityVisible: false
        ) == false)
    }

    @Test func testMetalCursorActivityKeepsFocusedBlinkingCursorVisible() {
        #expect(MetalTerminalRenderer.shouldHideCursorForBlinkFrame(
            style: .blinkBlock,
            hasFocus: true,
            cursorBlinkOn: false,
            cursorActivityVisible: true
        ) == false)
        #expect(MetalTerminalRenderer.isCursorActivityVisible(
            now: 1.0,
            visibleUntil: 1.7
        ) == true)
        #expect(MetalTerminalRenderer.isCursorActivityVisible(
            now: 1.7,
            visibleUntil: 1.7
        ) == false)
    }

    @Test func testMetalBlinkTimerRunsOnlyForVisibleFocusedBlinkingCursor() {
        #expect(MetalTerminalRenderer.shouldAnimateCursorBlink(
            style: .blinkBlock,
            hasFocus: true,
            cursorHidden: false
        ) == true)
        #expect(MetalTerminalRenderer.shouldAnimateCursorBlink(
            style: .blinkBlock,
            hasFocus: false,
            cursorHidden: false
        ) == false)
        #expect(MetalTerminalRenderer.shouldAnimateCursorBlink(
            style: .blinkBlock,
            hasFocus: true,
            cursorHidden: true
        ) == false)
        #expect(MetalTerminalRenderer.shouldAnimateCursorBlink(
            style: .steadyBlock,
            hasFocus: true,
            cursorHidden: false
        ) == false)
    }

    @Test func testMetalInactiveCursorOutlineMatchesClippedCaretStroke() {
        #expect(MetalTerminalRenderer.inactiveCursorOutlineThickness(scale: 1) == 1.5)
        #expect(MetalTerminalRenderer.inactiveCursorOutlineThickness(scale: 2) == 3)
    }

    @Test func testDectcemShowWhileScrolledBackKeepsCaretHidden() {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 120, height: 80))
        view.resize(cols: 10, rows: 4)

        let terminal = view.getTerminal()
        for i in 0..<20 {
            terminal.feed(text: "line \(i)\r\n")
        }
        #expect(view.caretView.superview === view)

        // Scroll to the top of scrollback: the live cursor row is below the
        // viewport, so the caret leaves the hierarchy.
        view.scrollTo(row: 0)
        #expect(view.caretView.superview == nil)

        // An application DECTCEM hide/show cycle (an AI CLI redrawing its
        // progress UI) must not re-add the caret while it is scrolled out of
        // view — this was the rapid caret flash over scrollback.
        terminal.feed(text: "\u{1b}[?25l")
        #expect(view.caretView.superview == nil)
        terminal.feed(text: "\u{1b}[?25h")
        #expect(view.caretView.superview == nil)

        // Returning to the bottom restores the caret.
        view.scrollToBottom()
        #expect(view.caretView.superview === view)
    }

    @Test func testDectcemShowRepositionsCaretWhenLiveCursorRowIsVisibleInScrollback() {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 120, height: 80))
        view.resize(cols: 10, rows: 4)

        let terminal = view.getTerminal()
        for i in 0..<20 {
            terminal.feed(text: "line \(i)\r\n")
        }
        // Park the live cursor on the top row of the live screen, then scroll
        // back two rows so that row is still visible at screen row 2.
        terminal.feed(text: "\u{1b}[H")
        view.scrollUp(lines: 2)

        let buffer = terminal.buffer
        #expect(buffer.yBase - buffer.yDisp == 2)
        #expect(view.caretView.superview === view)

        // A DECTCEM hide/show cycle must bring the caret back at the correct
        // viewport-relative position, not at whatever frame it last had.
        terminal.feed(text: "\u{1b}[?25l")
        #expect(view.caretView.superview == nil)
        view.caretView.frame.origin = CGPoint(x: -100, y: -100)
        terminal.feed(text: "\u{1b}[?25h")
        #expect(view.caretView.superview === view)

        let expectedY = view.frame.height - view.cellDimension.height * 3
        #expect(abs(view.caretFrame.origin.y - expectedY) < 0.001)
        #expect(abs(view.caretFrame.origin.x) < 0.001)
    }

    @Test func testDarkThemeUsesContrastingBlockCursorTextColor() throws {
        let theme = TerminalTheme.swiftTermDark
        let caretText = try #require(theme.caretText)

        #expect(caretText == theme.background)
        #expect(caretText != theme.caret)
    }
}
#endif
