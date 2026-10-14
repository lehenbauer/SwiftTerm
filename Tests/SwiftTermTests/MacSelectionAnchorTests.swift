#if os(macOS)
import AppKit
import Testing
@testable import SwiftTerm

// A native single-click drag selects from the pressed cell, even when AppKit
// delivers the first drag sample several cells away from the press. These
// tests drive the real AppKit handlers with NSEvents through an offscreen
// window and assert the selected text and range.
@MainActor
private final class SelectionGesture {
    let view: TerminalView
    let window: NSWindow
    private var eventNumber = 0

    init(width: CGFloat = 800, height: CGFloat = 400, scrollback: Int? = nil) {
        view = TerminalView(frame: NSRect(x: 0, y: 0, width: width, height: height),
                            font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular))
        window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: width, height: height),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        if let scrollback {
            view.terminal.changeScrollback(scrollback)
        }
    }

    var terminal: Terminal { view.terminal }

    static func content(_ n: Int) -> String {
        "ROW\(n) abcdefghijklmnopqrstuvwxyz 0123456789"
    }

    func feedRows(_ count: Int, prefix: String? = nil) {
        let rows = (0..<count).map { n in prefix.map { "\($0)\(n)" } ?? Self.content(n) }
        view.feed(text: rows.joined(separator: "\r\n"))
    }

    func rowText(_ row: Int) -> String {
        terminal.displayBuffer.lines[row].translateToString(trimRight: true)
    }

    /// View-local point at the center of the cell `p` (buffer-relative) under
    /// the current viewport. `screenRowOverride` places the point at an
    /// arbitrary screen row, including rows outside the view.
    func point(_ p: Position, screenRowOverride: Int? = nil) -> NSPoint {
        let screenRow = screenRowOverride ?? (p.row - terminal.displayBuffer.yDisp)
        return NSPoint(x: (CGFloat(p.col) + 0.25) * view.cellDimension.width,
                       y: view.frame.height - (CGFloat(screenRow) + 0.5) * view.cellDimension.height)
    }

    func event(_ type: NSEvent.EventType, at point: NSPoint,
               flags: NSEvent.ModifierFlags = [], clickCount: Int = 1) -> NSEvent {
        eventNumber += 1
        return NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil),
                                  modifierFlags: flags,
                                  timestamp: ProcessInfo.processInfo.systemUptime,
                                  windowNumber: window.windowNumber, context: nil,
                                  eventNumber: eventNumber, clickCount: clickCount,
                                  pressure: type == .leftMouseUp ? 0 : 1)!
    }

    func down(_ p: Position, flags: NSEvent.ModifierFlags = [], clickCount: Int = 1) {
        let e = event(.leftMouseDown, at: point(p), flags: flags, clickCount: clickCount)
        precondition(view.calculateMouseHit(with: e).grid == p, "press hit-test mismatch for \(p)")
        view.mouseDown(with: e)
    }

    func drag(_ p: Position, flags: NSEvent.ModifierFlags = []) {
        let e = event(.leftMouseDragged, at: point(p), flags: flags)
        precondition(view.calculateMouseHit(with: e).grid == p, "drag hit-test mismatch for \(p)")
        view.mouseDragged(with: e)
    }

    func dragToScreenRow(col: Int, screenRow: Int) {
        let e = event(.leftMouseDragged,
                      at: point(Position(col: col, row: 0), screenRowOverride: screenRow))
        view.mouseDragged(with: e)
    }

    func up(_ p: Position, flags: NSEvent.ModifierFlags = [], clickCount: Int = 1) {
        view.mouseUp(with: event(.leftMouseUp, at: point(p), flags: flags, clickCount: clickCount))
    }

    func typeKey(_ characters: String = "a") {
        let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                 timestamp: ProcessInfo.processInfo.systemUptime,
                                 windowNumber: window.windowNumber, context: nil,
                                 characters: characters, charactersIgnoringModifiers: characters,
                                 isARepeat: false, keyCode: 0)!
        view.keyDown(with: e)
    }

    var selection: SelectionService { view.selection }
    var selectedText: String { view.selection.getSelectedText() }
}

@MainActor
private func waitForRunLoop(_ seconds: TimeInterval) async {
    await withCheckedContinuation { continuation in
        let timer = Timer(timeInterval: seconds, repeats: false) { _ in
            continuation.resume()
        }
        RunLoop.main.add(timer, forMode: .common)
    }
}

@MainActor
@Suite(.serialized)
struct MacSelectionAnchorTests {
    private let esc = "\u{1b}"
    private typealias G = SelectionGesture

    // Rows 2...5 up to column 24 on ROW5 (the selection end is exclusive) —
    // the four-row selection the original report describes.
    private var fourRowText: String {
        [G.content(2), G.content(3), G.content(4), "ROW5 abcdefghijklmnopqrs"].joined(separator: "\n")
    }

    // MARK: - The reported defect

    @Test func displacedForwardDragStartsAtPress() {
        let g = SelectionGesture()
        g.feedRows(10)
        g.down(Position(col: 0, row: 2))
        g.drag(Position(col: 12, row: 3))
        g.drag(Position(col: 24, row: 5))
        g.up(Position(col: 24, row: 5))

        #expect(g.selection.active)
        #expect(g.selection.start == Position(col: 0, row: 2))
        #expect(g.selection.end == Position(col: 24, row: 5))
        #expect(g.selectedText == fourRowText)
    }

    @Test func displacedReverseDragStartsAtPress() {
        let g = SelectionGesture()
        g.feedRows(10)
        g.down(Position(col: 24, row: 5))
        g.drag(Position(col: 12, row: 4))
        g.drag(Position(col: 0, row: 2))
        g.up(Position(col: 0, row: 2))

        #expect(g.selection.active)
        #expect(g.selection.start == Position(col: 24, row: 5))
        #expect(g.selection.end == Position(col: 0, row: 2))
        #expect(g.selectedText == fourRowText)
    }

    @Test func singleDisplacedDragEventSelectsFourRows() {
        let g = SelectionGesture()
        g.feedRows(10)
        g.down(Position(col: 0, row: 2))
        g.drag(Position(col: 24, row: 5))

        #expect(g.selection.active)
        #expect(g.selection.hasSelectionRange)
        #expect(g.selection.start == Position(col: 0, row: 2))
        #expect(g.selection.end == Position(col: 24, row: 5))
        #expect(g.selectedText == fourRowText)
        g.up(Position(col: 24, row: 5))
        #expect(g.selectedText == fourRowText)
    }

    @Test func shiftPressWithoutSelectionStartsAtPress() {
        let g = SelectionGesture()
        g.feedRows(10)
        g.down(Position(col: 0, row: 2), flags: [.shift])
        g.drag(Position(col: 24, row: 5), flags: [.shift])

        #expect(g.selection.start == Position(col: 0, row: 2))
        #expect(g.selectedText == fourRowText)
    }

    @Test func pressThatClearsOldSelectionStartsNewSelectionAtPress() {
        let g = SelectionGesture()
        g.feedRows(10)
        g.selection.select(row: 8)
        g.down(Position(col: 0, row: 2))
        #expect(!g.selection.active)
        g.drag(Position(col: 24, row: 5))

        #expect(g.selection.start == Position(col: 0, row: 2))
        #expect(g.selectedText == fourRowText)
    }

    @Test func shiftBypassOfMouseReportingStartsAtPress() {
        let g = SelectionGesture()
        g.feedRows(10)
        g.view.feed(text: "\(esc)[?1002h\(esc)[?1006h")
        g.down(Position(col: 0, row: 2), flags: [.shift])
        g.drag(Position(col: 24, row: 5), flags: [.shift])

        #expect(g.selection.start == Position(col: 0, row: 2))
        #expect(g.selectedText == fourRowText)
    }

    // MARK: - Preserved gestures

    @Test func clickWithoutDragLeavesSelectionInactive() {
        let g = SelectionGesture()
        g.feedRows(10)
        g.down(Position(col: 3, row: 2))
        g.up(Position(col: 3, row: 2))

        #expect(!g.selection.active)
        #expect(!g.selection.hasSelectionRange)
    }

    @Test func shiftClickExtendsExistingSelection() {
        let g = SelectionGesture()
        g.feedRows(10)
        g.selection.setSelection(start: Position(col: 0, row: 1), end: Position(col: 5, row: 1))
        g.down(Position(col: 10, row: 3), flags: [.shift])
        #expect(g.selection.start == Position(col: 0, row: 1))
        #expect(g.selection.end == Position(col: 10, row: 3))
        g.drag(Position(col: 20, row: 4), flags: [.shift])
        g.up(Position(col: 20, row: 4), flags: [.shift])

        #expect(g.selection.start == Position(col: 0, row: 1))
        #expect(g.selection.end == Position(col: 20, row: 4))
    }

    @Test func doubleClickDragExtendsByWords() {
        let g = SelectionGesture()
        g.feedRows(10)
        g.down(Position(col: 7, row: 2))
        g.up(Position(col: 7, row: 2))
        g.down(Position(col: 7, row: 2), clickCount: 2)
        #expect(g.selectedText == "abcdefghijklmnopqrstuvwxyz")
        g.drag(Position(col: 34, row: 4))
        g.up(Position(col: 34, row: 4), clickCount: 2)

        #expect(g.selection.start == Position(col: 5, row: 2))
        #expect(g.selection.end == Position(col: 42, row: 4))
        #expect(g.selectedText == [
            "abcdefghijklmnopqrstuvwxyz 0123456789", G.content(3), G.content(4)
        ].joined(separator: "\n"))
    }

    @Test func tripleClickDragKeepsRowSelectionStart() {
        let g = SelectionGesture()
        g.feedRows(10)
        g.down(Position(col: 7, row: 2), clickCount: 3)
        #expect(g.selection.start == Position(col: 0, row: 2))
        g.drag(Position(col: 9, row: 4))

        #expect(g.selection.active)
        #expect(g.selection.start == Position(col: 0, row: 2))
        #expect(g.selection.end == Position(col: 9, row: 4))
    }

    @Test func earlierWordSelectionDoesNotLeakIntoNextDrag() {
        let g = SelectionGesture()
        g.feedRows(10)
        g.down(Position(col: 7, row: 2), clickCount: 2)
        g.up(Position(col: 7, row: 2), clickCount: 2)
        #expect(g.selection.active)

        g.down(Position(col: 7, row: 2))
        #expect(!g.selection.active)
        g.drag(Position(col: 9, row: 3))

        #expect(g.selection.start == Position(col: 7, row: 2))
        #expect(g.selection.end == Position(col: 9, row: 3))
        #expect(g.selectedText == "cdefghijklmnopqrstuvwxyz 0123456789\nROW3 abcd")
    }

    @Test func sameCellMotionThenDragStartsAtPress() {
        let g = SelectionGesture()
        g.feedRows(10)
        g.down(Position(col: 3, row: 2))
        g.drag(Position(col: 3, row: 2))
        #expect(g.selection.active)
        #expect(!g.selection.hasSelectionRange)
        g.drag(Position(col: 8, row: 2))

        #expect(g.selection.start == Position(col: 3, row: 2))
        #expect(g.selection.end == Position(col: 8, row: 2))
    }

    @Test func nextGestureStartsAtItsOwnPress() {
        let g = SelectionGesture()
        g.feedRows(10)
        g.down(Position(col: 0, row: 1))
        g.drag(Position(col: 5, row: 1))
        g.up(Position(col: 5, row: 1))

        g.down(Position(col: 2, row: 4))
        g.drag(Position(col: 10, row: 5))
        g.up(Position(col: 10, row: 5))

        #expect(g.selection.start == Position(col: 2, row: 4))
        #expect(g.selection.end == Position(col: 10, row: 5))
    }

    @Test func orphanDragWithoutPressStartsAtCurrentHit() {
        let g = SelectionGesture()
        g.feedRows(10)
        g.drag(Position(col: 12, row: 3))
        g.drag(Position(col: 24, row: 5))

        #expect(g.selection.start == Position(col: 12, row: 3))
        #expect(g.selection.end == Position(col: 24, row: 5))
    }

    @Test func dragAfterCompletedClickDoesNotReuseItsPress() {
        let g = SelectionGesture()
        g.feedRows(10)
        g.down(Position(col: 0, row: 1))
        g.up(Position(col: 0, row: 1))
        g.drag(Position(col: 12, row: 3))

        #expect(g.selection.start == Position(col: 12, row: 3))
    }

    // MARK: - Single use

    @Test func selectionClearedByLinefeedDoesNotRestartAtPress() {
        let g = SelectionGesture()
        g.feedRows(6)
        g.down(Position(col: 0, row: 1))
        g.drag(Position(col: 4, row: 2))
        #expect(g.selection.start == Position(col: 0, row: 1))
        g.view.feed(text: "\r\nOUT")
        #expect(!g.selection.active)
        g.drag(Position(col: 6, row: 3))

        #expect(g.selection.start == Position(col: 6, row: 3))
        #expect(g.selection.end == Position(col: 6, row: 3))
    }

    @Test func selectionClearedByKeyDoesNotRestartAtPress() {
        let g = SelectionGesture()
        g.feedRows(6)
        g.down(Position(col: 0, row: 1))
        g.drag(Position(col: 4, row: 2))
        g.typeKey()
        #expect(!g.selection.active)
        g.drag(Position(col: 6, row: 3))

        #expect(g.selection.start == Position(col: 6, row: 3))
    }

    @Test func keyBetweenPressAndFirstDragCancelsPressAnchor() {
        let g = SelectionGesture()
        g.feedRows(6)
        g.down(Position(col: 0, row: 1))
        g.typeKey()
        g.drag(Position(col: 6, row: 3))

        #expect(g.selection.start == Position(col: 6, row: 3))
    }

    @Test func focusLossBetweenPressAndFirstDragCancelsPressAnchor() {
        let g = SelectionGesture()
        g.feedRows(6)
        #expect(g.window.makeFirstResponder(g.view))
        g.down(Position(col: 0, row: 1))
        #expect(g.window.makeFirstResponder(nil))
        g.drag(Position(col: 6, row: 3))

        #expect(g.selection.start == Position(col: 6, row: 3))
    }

    // MARK: - Buffer changes between press and first drag

    @Test func streamingOutputBeforeFirstDragKeepsPress() {
        let g = SelectionGesture()
        g.feedRows(10)
        g.down(Position(col: 0, row: 2))
        g.view.feed(text: "\r\nOUT1\r\nOUT2")
        g.drag(Position(col: 24, row: 5))

        #expect(g.selection.start == Position(col: 0, row: 2))
        #expect(g.selectedText == fourRowText)
    }

    @Test func scrollingOutputBeforeFirstDragKeepsPressedLine() {
        let g = SelectionGesture()
        let rows = g.terminal.rows
        g.feedRows(rows)
        let pressRow = g.terminal.displayBuffer.yDisp + 2
        let pressedText = g.rowText(pressRow)
        g.down(Position(col: 0, row: pressRow))
        g.view.feed(text: "\r\nOUT1\r\nOUT2\r\nOUT3")
        #expect(g.terminal.displayBuffer.yDisp > 0)
        let target = Position(col: 4, row: g.terminal.displayBuffer.yDisp + 4)
        g.drag(target)

        #expect(g.selection.start == Position(col: 0, row: pressRow))
        #expect(g.selectedText.hasPrefix(pressedText + "\n"))
    }

    @Test func scrollbackTrimBeforeFirstDragFollowsPressedLine() {
        let g = SelectionGesture(scrollback: 5)
        let rows = g.terminal.rows
        g.feedRows(rows + 5, prefix: "LINE")
        let yDisp = g.terminal.displayBuffer.yDisp
        let pressRow = yDisp + 4
        #expect(g.rowText(pressRow) == "LINE\(pressRow)")
        g.down(Position(col: 2, row: pressRow))
        g.view.feed(text: "\r\nNEW1\r\nNEW2\r\nNEW3")
        // The buffer is at its cap, so three rows were trimmed from the top
        // and the pressed text now sits three rows higher.
        #expect(g.rowText(pressRow) != "LINE\(pressRow)")
        #expect(g.rowText(pressRow - 3) == "LINE\(pressRow)")
        let target = Position(col: 3, row: g.terminal.displayBuffer.yDisp + 6)
        g.drag(target)

        #expect(g.selection.start == Position(col: 2, row: pressRow - 3))
        #expect(g.selectedText.hasPrefix("NE\(pressRow)\n"))
    }

    @Test func historyPrependBeforeFirstDragFollowsPressedLine() {
        let g = SelectionGesture()
        g.feedRows(5, prefix: "LIVE")
        g.down(Position(col: 1, row: 2))
        let history = (0..<4).map { "HIST\($0)" }.joined(separator: "\r\n") + "\r\n"
        let inserted = g.view.prependScrollbackCapture(byteArray: ArraySlice(Array(history.utf8)))
        #expect(inserted > 0)
        #expect(g.rowText(2 + inserted) == "LIVE2")
        let target = Position(col: 3, row: 3 + inserted)
        g.drag(target)

        #expect(g.selection.start == Position(col: 1, row: 2 + inserted))
        #expect(g.selectedText == "IVE2\nLIV")
    }

    @Test func recycledPressedLineFallsBackToCurrentHit() {
        let g = SelectionGesture(scrollback: 5)
        let rows = g.terminal.rows
        g.feedRows(rows + 5, prefix: "LINE")
        let pressRow = g.terminal.displayBuffer.yDisp
        g.down(Position(col: 0, row: pressRow))
        // Push enough output that the pressed row leaves the capped buffer
        // and its storage is reused for new output.
        g.view.feed(text: (0..<(rows + 10)).map { "\r\nFRESH\($0)" }.joined())
        #expect(!(0..<g.terminal.displayBuffer.lines.count).contains {
            g.rowText($0) == "LINE\(pressRow)"
        })
        let target = Position(col: 4, row: g.terminal.displayBuffer.yDisp + 2)
        g.drag(target)

        #expect(g.selection.start == target)
        #expect(g.selection.end == target)
    }

    @Test func resetBeforeFirstDragFallsBackToCurrentHit() {
        let g = SelectionGesture()
        g.feedRows(10)
        g.down(Position(col: 0, row: 2))
        g.view.feed(text: "\(esc)c")
        g.feedRows(10)
        g.drag(Position(col: 24, row: 5))

        #expect(g.selection.start == Position(col: 24, row: 5))
    }

    @Test func alternateBufferSwitchBeforeFirstDragFallsBackToCurrentHit() {
        let g = SelectionGesture()
        g.feedRows(10)
        g.down(Position(col: 0, row: 2))
        g.view.feed(text: "\(esc)[?1049h")
        g.feedRows(10)
        g.drag(Position(col: 24, row: 5))

        #expect(g.terminal.isCurrentBufferAlternate)
        #expect(g.selection.start == Position(col: 24, row: 5))
    }

    @Test func alternateBufferRoundTripBeforeFirstDragKeepsPress() {
        let g = SelectionGesture()
        g.feedRows(10)
        g.down(Position(col: 0, row: 2))
        g.view.feed(text: "\(esc)[?1049hALT\(esc)[?1049l")
        g.drag(Position(col: 24, row: 5))

        #expect(g.selection.start == Position(col: 0, row: 2))
        #expect(g.selectedText == fourRowText)
    }

    @Test func columnResizeBeforeFirstDragFallsBackToCurrentHit() {
        let g = SelectionGesture()
        g.feedRows(10)
        let oldCols = g.terminal.cols
        g.down(Position(col: 30, row: 2))
        g.view.setFrameSize(NSSize(width: 400, height: 400))
        #expect(g.terminal.cols < oldCols)
        g.drag(Position(col: 5, row: 6))

        #expect(g.selection.start == Position(col: 5, row: 6))
        #expect(g.selection.end == Position(col: 5, row: 6))
    }

    // MARK: - Scrollback and auto-scroll

    @Test func pressInScrollbackStartsAtPress() {
        let g = SelectionGesture()
        g.feedRows(60, prefix: "LINE")
        g.view.scrollUp(lines: 20)
        let yDisp = g.terminal.displayBuffer.yDisp
        #expect(yDisp < g.terminal.displayBuffer.yBase)
        let press = Position(col: 0, row: yDisp + 2)
        g.down(press)
        g.drag(Position(col: 3, row: yDisp + 6))

        #expect(g.selection.start == press)
        #expect(g.selectedText == (2...6).map { n -> String in
            let text = "LINE\(yDisp + n)"
            return n == 6 ? String(text.prefix(3)) : text
        }.joined(separator: "\n"))
    }

    @Test func singleDragPastBottomEdgeStartsAtPressAndAutoScrolls() async {
        let g = SelectionGesture()
        g.feedRows(60, prefix: "LINE")
        g.view.scrollUp(lines: 30)
        let yDisp = g.terminal.displayBuffer.yDisp
        let press = Position(col: 0, row: yDisp + 1)
        g.down(press)
        g.dragToScreenRow(col: 2, screenRow: g.terminal.rows + 1)
        #expect(g.selection.start == press)
        let firstEnd = g.selection.end

        await waitForRunLoop(0.2)
        let scrolledYDisp = g.terminal.displayBuffer.yDisp
        let scrolledEnd = g.selection.end
        g.up(Position(col: 2, row: scrolledYDisp))

        #expect(scrolledYDisp > yDisp)
        #expect(scrolledEnd.row > firstEnd.row)
        #expect(g.selection.start == press)
    }

    // MARK: - Application mouse reporting

    @Test func reportedGestureSendsMotionWithoutSelecting() {
        let g = SelectionGesture()
        g.feedRows(10)
        g.view.feed(text: "\(esc)[?1002h\(esc)[?1006h")
        g.down(Position(col: 0, row: 2))
        g.drag(Position(col: 24, row: 5))
        g.up(Position(col: 24, row: 5))

        #expect(!g.selection.active)
    }

    @Test func reportingEnabledAfterPressCancelsPressAnchor() {
        let g = SelectionGesture()
        g.feedRows(10)
        g.down(Position(col: 0, row: 2))
        g.view.feed(text: "\(esc)[?1002h\(esc)[?1006h")
        g.drag(Position(col: 12, row: 3))
        #expect(!g.selection.active)
        g.view.feed(text: "\(esc)[?1002l")
        g.drag(Position(col: 24, row: 5))

        #expect(g.selection.start == Position(col: 24, row: 5))
    }

    @Test func reportedPressThenReportingDisabledStartsAtCurrentHit() {
        let g = SelectionGesture()
        g.feedRows(10)
        g.view.feed(text: "\(esc)[?1002h\(esc)[?1006h")
        g.down(Position(col: 0, row: 2))
        g.view.feed(text: "\(esc)[?1002l")
        g.drag(Position(col: 24, row: 5))

        #expect(g.selection.start == Position(col: 24, row: 5))
    }

    @Test func unreleasedPressDoesNotLeakIntoReportedGesture() {
        let g = SelectionGesture()
        g.feedRows(10)
        // A press whose release never reached the view, then a press the
        // application consumes, then reporting turns off mid-gesture.
        g.down(Position(col: 0, row: 2))
        g.view.feed(text: "\(esc)[?1002h\(esc)[?1006h")
        g.down(Position(col: 6, row: 3))
        g.view.feed(text: "\(esc)[?1002l")
        g.drag(Position(col: 24, row: 5))

        #expect(g.selection.start == Position(col: 24, row: 5))
    }

    @Test func disabledMouseReportingSelectsFromPress() {
        let g = SelectionGesture()
        g.feedRows(10)
        g.view.allowMouseReporting = false
        g.view.feed(text: "\(esc)[?1002h\(esc)[?1006h")
        g.down(Position(col: 0, row: 2))
        g.drag(Position(col: 24, row: 5))

        #expect(g.selection.start == Position(col: 0, row: 2))
        #expect(g.selectedText == fourRowText)
    }
}
#endif
