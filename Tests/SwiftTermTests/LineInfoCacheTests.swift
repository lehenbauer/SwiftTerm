import Foundation
import Testing

@testable import SwiftTerm

#if os(macOS)
final class LineInfoCacheTests {
    @Test func testCachedLineInfoTracksBufferLineGeneration() {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        view.resize(cols: 10, rows: 3)
        let terminal = view.getTerminal()

        terminal.feed(text: "abc")
        let line = terminal.displayBuffer.lines[0]
        _ = view.cachedLineInfo(row: 0, line: line, cols: terminal.cols)
        let firstGeneration = view.lineInfoCache[0]?.generation

        _ = view.cachedLineInfo(row: 0, line: line, cols: terminal.cols)
        #expect(view.lineInfoCache.count == 1)
        #expect(view.lineInfoCache[0]?.generation == firstGeneration)

        terminal.feed(text: "d")
        _ = view.cachedLineInfo(row: 0, line: line, cols: terminal.cols)
        #expect(view.lineInfoCache[0]?.generation == line.generation)
        #expect(view.lineInfoCache[0]?.generation != firstGeneration)
    }

    @Test func testInvalidatingOneLineInfoRowKeepsOtherRows() {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        view.resize(cols: 10, rows: 3)
        let terminal = view.getTerminal()

        terminal.feed(text: "abc\r\nxyz")
        let firstLine = terminal.displayBuffer.lines[0]
        let secondLine = terminal.displayBuffer.lines[1]
        _ = view.cachedLineInfo(row: 0, line: firstLine, cols: terminal.cols)
        _ = view.cachedLineInfo(row: 1, line: secondLine, cols: terminal.cols)

        view.invalidateLineInfoCache(row: 0)

        #expect(view.lineInfoCache[0] == nil)
        #expect(view.lineInfoCache[1] != nil)
    }
}
#endif
