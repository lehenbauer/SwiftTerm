import Testing

@testable import SwiftTerm

@Suite(.serialized)
final class InitialGeometryTests {
    @Test func wideTerminalConstructsBothBuffersWithCompleteTabStops() {
        let terminal = makeTerminal(options: TerminalOptions(cols: 132, rows: 48))

        #expect(terminal.getDims().cols == 132)
        #expect(terminal.getDims().rows == 48)
        #expect(terminal.normalBuffer.cols == 132)
        #expect(terminal.normalBuffer.rows == 48)
        #expect(terminal.altBuffer.cols == 132)
        #expect(terminal.altBuffer.rows == 48)

        terminal.feed(text: "\u{1b}[1;81H\t")
        #expect(terminal.buffer.x == 88)

        terminal.feed(text: "\u{1b}[?1049h\u{1b}[1;81H\t")
        #expect(terminal.buffer.x == 88)
    }

    @Test func customTabWidthAppliesAtConstruction() {
        let terminal = makeTerminal(options: TerminalOptions(tabStopWidth: 4))

        terminal.feed(text: "\t")

        #expect(terminal.buffer.x == 4)
    }

    @Test func invalidInitialGeometryAndTabWidthAreClamped() {
        let terminal = makeTerminal(options: TerminalOptions(cols: 1, rows: 0, tabStopWidth: 0))

        #expect(terminal.getDims().cols == 2)
        #expect(terminal.getDims().rows == 1)
        terminal.feed(text: "\t")
        #expect(terminal.buffer.x == 1)
    }

    @Test func constructionDoesNotNotifySizeChanged() {
        let delegate = RecordingTerminalDelegate()

        _ = Terminal(delegate: delegate, options: TerminalOptions(cols: 132, rows: 48))

        #expect(delegate.sizeChangedCount == 0)
    }

    @Test func sameSizeSetupResetsScrollRegionsOnBothBuffers() {
        let terminal = makeTerminal()
        terminal.feed(text: "\u{1b}[?1049h\u{1b}[2;10r\u{1b}[?1049l\u{1b}[3;12r")

        terminal.setup()

        #expect(terminal.normalBuffer.scrollTop == 0)
        #expect(terminal.normalBuffer.scrollBottom == 24)
        #expect(terminal.altBuffer.scrollTop == 0)
        #expect(terminal.altBuffer.scrollBottom == 24)
    }

    @Test func resetSetupResizesBothBuffers() {
        let terminal = makeTerminal()
        terminal.options.cols = 100
        terminal.options.rows = 30

        terminal.setup(isReset: true)

        #expect(terminal.normalBuffer.cols == 100)
        #expect(terminal.normalBuffer.rows == 30)
        #expect(terminal.altBuffer.cols == 100)
        #expect(terminal.altBuffer.rows == 30)
    }

    @Test func setupAppliesChangedTabWidthAtUnchangedSize() {
        let terminal = makeTerminal()
        terminal.options.tabStopWidth = 4

        terminal.setup()
        terminal.feed(text: "\t")

        #expect(terminal.buffer.x == 4)
    }

    @Test func setupPreservesCustomTabStopWhenWidthIsUnchanged() {
        let terminal = makeTerminal()
        terminal.feed(text: "\u{1b}[1;5H\u{1b}H\u{1b}[1;1H")

        terminal.setup()
        terminal.feed(text: "\t")

        #expect(terminal.buffer.x == 4)
    }

    @Test func optionsThenSetupGrowInstallsStopsPastOldWidth() {
        let terminal = makeTerminal()
        terminal.options.cols = 132

        terminal.setup()
        terminal.feed(text: "\u{1b}[1;81H\t")

        #expect(terminal.getDims().cols == 132)
        #expect(terminal.buffer.x == 88)
    }

    @Test func legacyConstructionKeepsDefaultGeometryAndTabs() {
        let terminal = makeTerminal()

        terminal.feed(text: "\t")

        #expect(terminal.getDims().cols == 80)
        #expect(terminal.getDims().rows == 25)
        #expect(terminal.buffer.x == 8)
    }

    private func makeTerminal(options: TerminalOptions = .default) -> Terminal {
        Terminal(delegate: RecordingTerminalDelegate(), options: options)
    }
}

private final class RecordingTerminalDelegate: TerminalDelegate {
    private(set) var sizeChangedCount = 0

    func sizeChanged(source: Terminal) {
        sizeChangedCount += 1
    }

    func send(source: Terminal, data: ArraySlice<UInt8>) {}
}
