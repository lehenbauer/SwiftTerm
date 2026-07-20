#if os(macOS)
import AppKit
import Testing

@testable import SwiftTerm

@MainActor
@Suite(.serialized)
final class InitialGeometryViewTests {
    @Test func fixedGridExistsBeforeLayoutAndIgnoresFrameChanges() {
        let view = makeView(initialGeometry: .grid(cols: 80, rows: 48), autoResizeGrid: false)

        #expect(view.terminal.cols == 80)
        #expect(view.terminal.rows == 48)
        view.feed(text: String(repeating: "x", count: 100))
        #expect(view.terminal.buffer.x == 20)
        #expect(view.terminal.buffer.y == 1)

        view.setFrameSize(NSSize(width: 400, height: 240))
        #expect(view.terminal.cols == 80)
        #expect(view.terminal.rows == 48)
    }

    @Test func followViewGridResizesAfterConstruction() {
        let view = makeView(initialGeometry: .grid(cols: 80, rows: 48), autoResizeGrid: true)

        view.setFrameSize(NSSize(width: view.cellDimension.width * 40,
                                 height: view.cellDimension.height * 12))

        #expect(view.terminal.cols != 80)
        #expect(view.terminal.rows == 12)
    }

    @Test func explicitGridWinsOverNonzeroFrame() {
        let view = makeView(frame: CGRect(x: 0, y: 0, width: 800, height: 600),
                            initialGeometry: .grid(cols: 100, rows: 40),
                            autoResizeGrid: false)

        #expect(view.terminal.cols == 100)
        #expect(view.terminal.rows == 40)
    }

    @Test func zeroFrameWithoutGeometryUsesOptionsGrid() {
        let view = makeView(options: TerminalOptions(cols: 132, rows: 48),
                            initialGeometry: nil, autoResizeGrid: false)

        #expect(view.terminal.cols == 132)
        #expect(view.terminal.rows == 48)
    }

    @Test func viewportUsesLiveResizeGeometryMath() {
        let size = CGSize(width: 720, height: 420)
        let view = makeView(initialGeometry: .viewport(size), autoResizeGrid: true)
        let expectedCols = Int(view.getEffectiveWidth(size: size) / view.cellDimension.width)
        let expectedRows = Int(size.height / view.cellDimension.height)

        #expect(view.terminal.cols == expectedCols)
        #expect(view.terminal.rows == expectedRows)
    }

    @Test func invalidViewportsFallBackToOptionsGrid() {
        let options = TerminalOptions(cols: 90, rows: 30)
        let invalidSizes = [
            CGSize(width: CGFloat.nan, height: 300),
            CGSize(width: 300, height: 0),
            CGSize(width: -1, height: 300)
        ]

        for size in invalidSizes {
            let view = makeView(options: options, initialGeometry: .viewport(size), autoResizeGrid: false)
            #expect(view.terminal.cols == 90)
            #expect(view.terminal.rows == 30)
        }
    }

    @Test func sameFrameFirstLayoutDoesNotResizeOrNotify() {
        let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let view = TerminalView(frame: frame)
        let initialDims = view.terminal.getDims()
        let delegate = RecordingViewDelegate()
        view.terminalDelegate = delegate

        view.setFrameSize(frame.size)

        #expect(view.terminal.cols == initialDims.cols)
        #expect(view.terminal.rows == initialDims.rows)
        #expect(delegate.sizeChangedCount == 0)
    }

    @Test func nonGeometryOptionsSurviveGridOverride() {
        let options = TerminalOptions(cols: 80, rows: 25, termName: "test-term", scrollback: 1234)
        let view = makeView(options: options, initialGeometry: .grid(cols: 100, rows: 40),
                            autoResizeGrid: false)

        #expect(view.terminal.options.scrollback == 1234)
        #expect(view.terminal.options.termName == "test-term")
        #expect(view.terminal.cols == 100)
        #expect(view.terminal.rows == 40)
    }

    @Test func legacyInitializersKeepZeroFallbackAndFrameDerivation() {
        let zeroView = TerminalView(frame: .zero)
        #expect(zeroView.terminal.cols == 80)
        #expect(zeroView.terminal.rows == 25)

        let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let framedView = TerminalView(frame: frame)
        #expect(framedView.terminal.cols == Int(framedView.getEffectiveWidth(size: frame.size) /
                                               framedView.cellDimension.width))
        #expect(framedView.terminal.rows == Int(frame.height / framedView.cellDimension.height))
    }

    @Test func fontResetUsesTheSameEffectiveWidthAsBoundsResize() {
        let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let view = TerminalView(frame: frame)
        view.followsSystemScrollerStyle = false
        view.scrollerStyle = .legacy
        view.setFrameSize(frame.size)
        let dimensionsAfterBoundsResize = view.terminal.getDims()

        view.font = view.font

        #expect(view.terminal.cols == dimensionsAfterBoundsResize.cols)
        #expect(view.terminal.rows == dimensionsAfterBoundsResize.rows)
    }

    @Test func localProcessViewPassesInitialGridToWindowSize() {
        let view = LocalProcessTerminalView(frame: .zero, font: nil,
                                            terminalOptions: .default,
                                            initialGeometry: .grid(cols: 120, rows: 40),
                                            autoResizeGrid: false)

        let windowSize = view.getWindowSize()
        #expect(windowSize.ws_col == 120)
        #expect(windowSize.ws_row == 40)
    }

    private func makeView(frame: CGRect = .zero, options: TerminalOptions = .default,
                          initialGeometry: TerminalInitialGeometry?,
                          autoResizeGrid: Bool) -> TerminalView {
        TerminalView(frame: frame, font: nil, terminalOptions: options,
                     initialGeometry: initialGeometry, autoResizeGrid: autoResizeGrid)
    }
}

private final class RecordingViewDelegate: TerminalViewDelegate {
    private(set) var sizeChangedCount = 0

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        sizeChangedCount += 1
    }

    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func send(source: TerminalView, data: ArraySlice<UInt8>) {}
    func scrolled(source: TerminalView, position: Double) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
    func bell(source: TerminalView) {}
    func clipboardCopy(source: TerminalView, content: Data) {}
    func clipboardRead(source: TerminalView) -> Data? { nil }
    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}
#endif
