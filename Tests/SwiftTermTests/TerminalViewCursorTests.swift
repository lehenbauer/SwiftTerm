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
}
#endif
