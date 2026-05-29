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
            cursorBlinkOn: false
        ) == false)
        #expect(MetalTerminalRenderer.shouldHideCursorForBlinkFrame(
            style: .blinkUnderline,
            hasFocus: false,
            cursorBlinkOn: false
        ) == false)
        #expect(MetalTerminalRenderer.shouldHideCursorForBlinkFrame(
            style: .blinkBar,
            hasFocus: false,
            cursorBlinkOn: false
        ) == false)
    }

    @Test func testMetalBlinkFrameStillHidesFocusedBlinkingCursor() {
        #expect(MetalTerminalRenderer.shouldHideCursorForBlinkFrame(
            style: .blinkBlock,
            hasFocus: true,
            cursorBlinkOn: false
        ) == true)
        #expect(MetalTerminalRenderer.shouldHideCursorForBlinkFrame(
            style: .steadyBlock,
            hasFocus: true,
            cursorBlinkOn: false
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

    @Test func testDarkThemeUsesContrastingBlockCursorTextColor() throws {
        let theme = TerminalTheme.swiftTermDark
        let caretText = try #require(theme.caretText)

        #expect(caretText == theme.background)
        #expect(caretText != theme.caret)
    }
}
#endif
