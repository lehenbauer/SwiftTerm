import XCTest
@testable import SwiftTerm

final class TerminalExtraHistoryRangeTests: XCTestCase {
    func testExtraViewportIncludesHistoryWithoutChangingLiveGridCoordinates() {
        XCTAssertEqual(terminalExtraHistoryRange(enabled: true, alternate: false,
            displayRow: 80, gridRows: 20, lineCount: 100, viewportFirstRow: 60, viewportRows: 40), 60..<100)
    }

    func testHistoryBrowsingKeepsTheSelectedTopRow() {
        XCTAssertEqual(terminalExtraHistoryRange(enabled: true, alternate: false,
            displayRow: 10, gridRows: 20, lineCount: 100, viewportFirstRow: 10, viewportRows: 40), 10..<50)
    }

    func testShortHistoryAndOverscrollAreBounded() {
        XCTAssertEqual(terminalExtraHistoryRange(enabled: true, alternate: false,
            displayRow: 5, gridRows: 20, lineCount: 25, viewportFirstRow: -5, viewportRows: 40), 0..<25)
    }

    func testOrdinarySizedDisabledAndAlternateViewsKeepExistingRendering() {
        for (enabled, alternate, rows) in [(false, false, 40), (true, true, 40), (true, false, 20), (true, false, 10)] {
            XCTAssertNil(terminalExtraHistoryRange(enabled: enabled, alternate: alternate,
                displayRow: 80, gridRows: 20, lineCount: 100, viewportFirstRow: 60, viewportRows: rows))
        }
    }
}
