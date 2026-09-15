#if os(iOS) || os(visionOS)
import UIKit
import XCTest
@testable import SwiftTerm

/// Exercise the real UIKit view/model integration with deterministic gesture
/// phases. Physical momentum and gesture arbitration still need a device check.
@MainActor
final class IOSScrollbackGestureTests: XCTestCase {
    private final class GestureView: TerminalView {
        var simulatedTracking = false
        var simulatedDecelerating = false
        var contentSizeChanged: (() -> Void)?
        override var isTracking: Bool { simulatedTracking }
        override var isDecelerating: Bool { simulatedDecelerating }
        override var contentSize: CGSize {
            didSet { contentSizeChanged?() }
        }
    }

    private final class ScrollDelegate: TerminalViewDelegate {
        var positions: [Double] = []
        var onScroll: ((TerminalView) -> Void)?
        func scrolled(source: TerminalView, position: Double) {
            positions.append(position)
            onScroll?(source)
        }
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func send(source: TerminalView, data: ArraySlice<UInt8>) {}
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }

    private func fixture() -> (GestureView, ScrollDelegate) {
        let view = GestureView(
            frame: CGRect(x: 0, y: 0, width: 464, height: 700), font: nil,
            terminalOptions: TerminalOptions(cols: 58, rows: 50, scrollback: 2_000),
            initialGeometry: .grid(cols: 58, rows: 50), autoResizeGrid: false
        )
        view.contentInsetAdjustmentBehavior = .never
        view.frame.size.height = 50 * view.cellDimension.height
        view.terminal.feed(text: (0..<150).map { "existing \($0)" }.joined(separator: "\r\n"))
        view.updateScroller()
        let observer = ScrollDelegate()
        view.terminalDelegate = observer
        XCTAssertFalse(view.userScrolling)
        return (view, observer)
    }

    private func drag(_ view: GestureView, toRow row: CGFloat) {
        view.simulatedTracking = true
        view.scrollViewWillBeginDragging(view)
        view.contentOffset.y = row * view.cellDimension.height
        view.scrollViewDidScroll(view)
    }

    private func coast(_ view: GestureView, toRow row: CGFloat) {
        view.simulatedTracking = false
        view.simulatedDecelerating = true
        view.scrollViewDidEndDragging(view, willDecelerate: true)
        view.contentOffset.y = row * view.cellDimension.height
        view.scrollViewDidScroll(view)
    }

    private func appendOutput(_ view: GestureView) {
        view.terminal.feed(text: "\r\nnew output")
        view.updateScroller()
    }

    func testUpwardMomentumNotifiesTopAndDoesNotSnapBackOnOutput() {
        let (view, observer) = fixture()
        drag(view, toRow: 46.2)
        coast(view, toRow: 0)
        XCTAssertEqual(view.terminal.buffer.yDisp, 0)
        XCTAssertEqual(observer.positions.last, 0)
        view.simulatedDecelerating = false
        view.scrollViewDidEndDecelerating(view)
        appendOutput(view)
        XCTAssertEqual(view.contentOffset.y, 0, accuracy: 0.01)
        XCTAssertEqual(view.terminal.buffer.yDisp, 0)
        XCTAssertTrue(view.userScrolling)
        XCTAssertTrue(view.terminal.userScrolling)
    }

    func testQuietDragNotifiesOncePerRowAfterStateIsConsistent() {
        let (view, observer) = fixture()
        observer.onScroll = { source in
            XCTAssertEqual(source.userScrolling, source.terminal.userScrolling)
            XCTAssertTrue(source.userScrolling)
        }
        drag(view, toRow: 2.25)
        XCTAssertEqual(observer.positions.count, 1)
        view.contentOffset.y = 2.3 * view.cellDimension.height
        view.scrollViewDidScroll(view)
        XCTAssertEqual(observer.positions.count, 1)
        view.contentOffset.y = 0
        view.scrollViewDidScroll(view)
        XCTAssertEqual(observer.positions, [0.02, 0])
    }

    func testFinalGestureCallbacksSynchronizeAfterUIKitClearsFlags() {
        for momentum in [false, true] {
            let (view, _) = fixture()
            drag(view, toRow: 46)
            // UIKit can deliver the final offset after clearing its flags.
            view.simulatedTracking = false
            view.contentOffset.y = 2.25 * view.cellDimension.height
            let finalOffset = view.contentOffset.y
            // An output tick can run before UIKit delivers the end callback.
            appendOutput(view)
            XCTAssertEqual(view.contentOffset.y, finalOffset, accuracy: 0.01)
            if momentum {
                view.scrollViewDidEndDecelerating(view)
            } else {
                view.scrollViewDidEndDragging(view, willDecelerate: false)
            }
            XCTAssertEqual(view.terminal.buffer.yDisp, 2)
            appendOutput(view)
            XCTAssertEqual(view.contentOffset.y, finalOffset, accuracy: 0.01)
        }
    }

    func testFollowingMomentumCannotReenterManualModeWhenOutputGrows() {
        let (view, _) = fixture()
        view.simulatedDecelerating = true
        appendOutput(view)
        XCTAssertFalse(view.userScrolling)
        XCTAssertFalse(view.terminal.userScrolling)
        XCTAssertEqual(view.terminal.buffer.yDisp, view.terminal.buffer.yBase)
        XCTAssertEqual(view.contentOffset.y, view.contentSize.height - view.bounds.height, accuracy: 0.01)
    }

    func testManualFlingToBottomResumesFollowingDuringMomentum() {
        let (view, observer) = fixture()
        drag(view, toRow: 5)
        coast(view, toRow: CGFloat(view.terminal.buffer.yBase))
        XCTAssertEqual(observer.positions.last, 1)
        appendOutput(view)
        XCTAssertFalse(view.userScrolling)
        XCTAssertFalse(view.terminal.userScrolling)
        XCTAssertEqual(view.contentOffset.y, view.contentSize.height - view.bounds.height, accuracy: 0.01)
    }

    func testStreamingWhileCoastingKeepsHistoryUntilCurrentBottomIsReached() {
        let (view, _) = fixture()
        drag(view, toRow: 10)
        for row in [20, 40, 60] {
            coast(view, toRow: CGFloat(row))
            appendOutput(view)
            XCTAssertEqual(view.terminal.buffer.yDisp, row)
            XCTAssertEqual(view.contentOffset.y, CGFloat(row) * view.cellDimension.height, accuracy: 0.01)
            XCTAssertTrue(view.userScrolling)
        }
        coast(view, toRow: CGFloat(view.terminal.buffer.yBase))
        appendOutput(view)
        XCTAssertFalse(view.userScrolling)
        XCTAssertEqual(view.contentOffset.y, view.contentSize.height - view.bounds.height, accuracy: 0.01)
    }

    func testProgrammaticScrollStillMovesWhenParkedInHistory() {
        let (view, _) = fixture()
        drag(view, toRow: 10.25)
        view.simulatedTracking = false
        view.scrollViewDidEndDragging(view, willDecelerate: false)
        view.scrollTo(row: 30)
        XCTAssertEqual(view.terminal.buffer.yDisp, 30)
        XCTAssertEqual(view.contentOffset.y, 30 * view.cellDimension.height, accuracy: 0.01)
        appendOutput(view)
        XCTAssertEqual(view.contentOffset.y, 30 * view.cellDimension.height, accuracy: 0.01)
    }

    func testPrependPreservesAnchorAndFractionDuringDragCoastAndIdle() {
        for phase in 0..<3 {
            let (view, observer) = fixture()
            drag(view, toRow: 2.25)
            if phase > 0 { coast(view, toRow: 1.25) }
            if phase == 2 {
                view.simulatedDecelerating = false
                view.scrollViewDidEndDecelerating(view)
            }
            let anchor = view.terminal.buffer.linesTop + view.terminal.buffer.yDisp
            let offset = view.contentOffset.y
            observer.positions.removeAll()
            // Model the synchronous offset clamp UIKit can emit while its
            // content size changes. It must not overwrite the rebased yDisp.
            view.contentSizeChanged = { [weak view] in
                view?.contentOffset.y = 0
                view?.contentSizeChanged = nil
            }
            let capture = (0..<1_000).map { "older \($0)" }.joined(separator: "\r\n")
            let inserted = view.prependScrollbackCapture(byteArray: Array(capture.utf8)[...])
            XCTAssertEqual(inserted, 1_000)
            XCTAssertEqual(view.terminal.buffer.linesTop + view.terminal.buffer.yDisp, anchor)
            XCTAssertEqual(view.contentOffset.y, offset + 1_000 * view.cellDimension.height, accuracy: 0.01)
            XCTAssertEqual(observer.positions.count, 1)
            appendOutput(view)
            XCTAssertEqual(view.contentOffset.y, offset + 1_000 * view.cellDimension.height, accuracy: 0.01)
        }
    }

    func testPrependDuringTopBounceAnchorsFirstExistingRow() {
        let (view, _) = fixture()
        drag(view, toRow: 2)
        coast(view, toRow: -5)
        let originalTop = view.terminal.buffer.linesTop
        let inserted = view.prependScrollbackCapture(byteArray: Array("older A\r\nolder B".utf8)[...])
        XCTAssertEqual(inserted, 2)
        XCTAssertEqual(view.terminal.buffer.linesTop + view.terminal.buffer.yDisp, originalTop)
        XCTAssertEqual(view.contentOffset.y, 2 * view.cellDimension.height, accuracy: 0.01)
    }

    func testProgrammaticLayoutOffsetDoesNotEnterManualMode() {
        let (view, observer) = fixture()
        view.contentOffset.y = 3.25 * view.cellDimension.height
        view.scrollViewDidScroll(view)
        view.scrollViewDidEndDecelerating(view)
        XCTAssertFalse(view.userScrolling)
        XCTAssertFalse(view.terminal.userScrolling)
        XCTAssertEqual(view.terminal.buffer.yDisp, view.terminal.buffer.yBase)
        XCTAssertTrue(observer.positions.isEmpty)
        view.updateScroller()
        XCTAssertEqual(view.contentOffset.y, view.contentSize.height - view.bounds.height, accuracy: 0.01)
    }

    func testFractionalViewportAndBottomInsetStillResumeFollowing() {
        let (view, _) = fixture()
        view.frame.size.height += view.cellDimension.height / 3
        view.contentInset.bottom = 25
        view.updateScroller()
        drag(view, toRow: 4)
        let bottom = view.contentSize.height - view.bounds.height + view.adjustedContentInset.bottom
        coast(view, toRow: (bottom - view.cellDimension.height / 4) / view.cellDimension.height)
        XCTAssertFalse(view.userScrolling)
        appendOutput(view)
        // The existing follow policy clamps row alignment to the UIKit maximum.
        XCTAssertEqual(view.contentOffset.y,
                       min(CGFloat(view.terminal.buffer.yDisp) * view.cellDimension.height,
                           view.contentSize.height - view.bounds.height + view.adjustedContentInset.bottom), accuracy: 0.01)
    }

    func testEmptyAndAlternatePrependDoNotChangeViewportOrNotify() {
        let (view, observer) = fixture()
        drag(view, toRow: 3)
        coast(view, toRow: 2)
        let oldOffset = view.contentOffset
        observer.positions.removeAll()
        XCTAssertEqual(view.prependScrollbackCapture(byteArray: []), 0)
        XCTAssertEqual(view.contentOffset, oldOffset)
        XCTAssertTrue(observer.positions.isEmpty)
        view.terminal.feed(text: "\u{1b}[?1049h")
        view.updateScroller()
        let alternateOffset = view.contentOffset
        observer.positions.removeAll()
        XCTAssertEqual(view.prependScrollbackCapture(byteArray: Array("older".utf8)[...]), 0)
        XCTAssertEqual(view.contentOffset, alternateOffset)
        XCTAssertTrue(observer.positions.isEmpty)
    }
}
#endif
