#if os(macOS)
import AppKit
import Foundation
import Testing

@testable import SwiftTerm

@MainActor
@Suite(.serialized)
final class MirrorGridPinTests {
    @Test func frameShrinkDoesNotMutateGridWhenAutoResizeIsDisabled() {
        let view = makeView()
        view.autoResizeGrid = false

        view.setFrameSize(NSSize(
            width: view.cellDimension.width * 40,
            height: view.cellDimension.height * 12
        ))

        #expect(view.terminal.cols == 80)
        #expect(view.terminal.rows == 24)
    }

    @Test func frameShrinkKeepsHistoricalGridMutationWhenAutoResizeIsEnabled() {
        let view = makeView()

        view.setFrameSize(NSSize(
            width: view.cellDimension.width * 40,
            height: view.cellDimension.height * 12
        ))

        #expect(view.terminal.cols != 80)
        #expect(view.terminal.rows != 24)
    }

    @Test func fontChangeDoesNotMutateGridWhenAutoResizeIsDisabled() {
        let view = makeView()
        view.autoResizeGrid = false
        let originalFontSize = view.font.pointSize

        view.font = NSFont.monospacedSystemFont(ofSize: originalFontSize + 8, weight: .regular)

        #expect(view.terminal.cols == 80)
        #expect(view.terminal.rows == 24)
    }

    @Test func preservingResizeKeepsTerminalModesAndAlternateScreen() {
        let view = makeView()
        let terminal = view.terminal!
        terminal.feed(text: "\u{1b}[?1049h")
        terminal.applicationCursor = true
        terminal.originMode = true
        terminal.setWraparound(false)
        terminal.setMarginMode(true)
        terminal.cursorHidden = true
        terminal.buffer.scrollTop = 4
        terminal.buffer.scrollBottom = 19
        terminal.buffer.marginLeft = 9
        terminal.buffer.marginRight = 69

        view.resize(cols: 100, rows: 30, preservingTerminalModes: true)

        #expect(terminal.cols == 100)
        #expect(terminal.rows == 30)
        #expect(terminal.isCurrentBufferAlternate)
        #expect(terminal.applicationCursor)
        #expect(terminal.originMode)
        #expect(!terminal.wraparound)
        #expect(terminal.marginMode)
        #expect(terminal.cursorHidden)
        #expect(terminal.buffer.scrollTop == 4)
        #expect(terminal.buffer.scrollBottom == 19)
        #expect(terminal.buffer.marginLeft == 9)
        #expect(terminal.buffer.marginRight == 69)
    }

    @Test func compatibilityResizeStillSoftResetsTerminalModes() {
        let view = makeView()
        let terminal = view.terminal!
        terminal.applicationCursor = true
        terminal.originMode = true
        terminal.setWraparound(false)
        terminal.cursorHidden = true
        terminal.buffer.scrollTop = 4
        terminal.buffer.scrollBottom = 19

        view.resize(cols: 100, rows: 30)

        #expect(!terminal.applicationCursor)
        #expect(!terminal.originMode)
        #expect(terminal.wraparound)
        #expect(!terminal.cursorHidden)
        #expect(terminal.buffer.scrollTop == 0)
        #expect(terminal.buffer.scrollBottom == 29)
    }

    private func makeView() -> TerminalView {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        view.resize(cols: 80, rows: 24)
        view.setFrameSize(NSSize(
            width: view.cellDimension.width * 80,
            height: view.cellDimension.height * 24
        ))
        return view
    }
}
#endif
