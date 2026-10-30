#if os(iOS) || os(visionOS)
import UIKit
import XCTest
@testable import SwiftTerm

/// Printable hardware keys (fork `324c77f`): sent and auto-repeated from
/// `pressesBegan`, released on `pressesEnded`, and never taken while an input
/// method is composing (marked text) or when Command/Option/Control give the
/// key another meaning.
@MainActor
final class IOSPrintableKeyRepeatTests: XCTestCase {
    private final class FakeKey: UIKey {
        private let code: UIKeyboardHIDUsage
        private let text: String
        private let flags: UIKeyModifierFlags
        init(code: UIKeyboardHIDUsage, text: String, flags: UIKeyModifierFlags = []) {
            self.code = code
            self.text = text
            self.flags = flags
            super.init()
        }
        required init?(coder: NSCoder) { nil }
        override var keyCode: UIKeyboardHIDUsage { code }
        override var characters: String { text }
        override var charactersIgnoringModifiers: String { text }
        override var modifierFlags: UIKeyModifierFlags { flags }
    }

    private final class FakePress: UIPress {
        private let fakeKey: UIKey
        init(key: UIKey) {
            fakeKey = key
            super.init()
        }
        override var key: UIKey? { fakeKey }
    }

    private final class ByteRecorder: TerminalViewDelegate {
        var sends: [[UInt8]] = []
        func send(source: TerminalView, data: ArraySlice<UInt8>) { sends.append(Array(data)) }
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func scrolled(source: TerminalView, position: Double) {}
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }

    private var views: [TerminalView] = []

    override func tearDown() {
        for view in views {
            view.keyRepeat?.invalidate()
            view.updateUiClosed()
        }
        views.removeAll()
        super.tearDown()
    }

    private func makeView() -> (TerminalView, ByteRecorder) {
        let view = TerminalView(
            frame: CGRect(x: 0, y: 0, width: 400, height: 300), font: nil,
            terminalOptions: TerminalOptions(cols: 40, rows: 10, scrollback: 100),
            initialGeometry: .grid(cols: 40, rows: 10), autoResizeGrid: false)
        let recorder = ByteRecorder()
        view.terminalDelegate = recorder
        views.append(view)
        return (view, recorder)
    }

    private func spin(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds))
    }

    private let letterA: [UInt8] = Array("a".utf8)

    func testLegacyPrintableKeySendsRepeatsAndStopsOnRelease() {
        let (view, recorder) = makeView()
        let press = FakePress(key: FakeKey(code: .keyboardA, text: "a"))

        view.pressesBegan([press], with: nil)
        XCTAssertEqual(recorder.sends, [letterA])
        XCTAssertNotNil(view.keyRepeat)

        spin(0.75)
        XCTAssertGreaterThanOrEqual(recorder.sends.count, 3)
        XCTAssertTrue(recorder.sends.allSatisfy { $0 == letterA })

        view.pressesEnded([press], with: nil)
        XCTAssertNil(view.keyRepeat)
        let afterEnd = recorder.sends.count
        spin(0.5)
        XCTAssertEqual(recorder.sends.count, afterEnd)
    }

    func testComposingInputMethodKeepsPrintableKeys() {
        let (view, recorder) = makeView()
        view.setMarkedText("k", selectedRange: NSRange(location: 1, length: 0))
        XCTAssertNotNil(view.markedTextRange)
        let sendsBefore = recorder.sends.count

        let press = FakePress(key: FakeKey(code: .keyboardA, text: "a"))
        view.pressesBegan([press], with: nil)

        XCTAssertEqual(recorder.sends.count, sendsBefore, "a composing key must go to the input method")
        XCTAssertNil(view.keyRepeat, "a composing key must not auto-repeat as terminal input")
        view.pressesEnded([press], with: nil)
    }

    /// Command keeps the key for the host and sends nothing; Option may act
    /// as Meta (ESC-prefixed, repeating). Neither sends the key as plain text.
    func testModifiedPrintableKeysAreNotTakenAsText() {
        let (view, recorder) = makeView()
        let command = FakePress(key: FakeKey(code: .keyboardA, text: "a", flags: .command))
        view.pressesBegan([command], with: nil)
        XCTAssertTrue(recorder.sends.isEmpty, "Command+A sent \(recorder.sends)")
        XCTAssertNil(view.keyRepeat, "Command+A started a repeat")
        view.pressesEnded([command], with: nil)

        let option = FakePress(key: FakeKey(code: .keyboardA, text: "a", flags: .alternate))
        view.pressesBegan([option], with: nil)
        XCTAssertFalse(recorder.sends.contains(letterA), "Option+A sent plain text")
        view.pressesEnded([option], with: nil)
        XCTAssertNil(view.keyRepeat)
    }

    func testKittyPrintableKeyIsEncodedAndRepeats() {
        let (view, recorder) = makeView()
        view.feed(text: "\u{1b}[=1u")
        XCTAssertFalse(view.keyboardEnhancementFlags.isEmpty)
        let press = FakePress(key: FakeKey(code: .keyboardA, text: "a"))

        view.pressesBegan([press], with: nil)
        XCTAssertEqual(recorder.sends.first, letterA, "disambiguate mode sends plain text keys as text")
        XCTAssertNotNil(view.keyRepeat)
        spin(0.75)
        XCTAssertGreaterThanOrEqual(recorder.sends.count, 3)

        view.pressesEnded([press], with: nil)
        XCTAssertNil(view.keyRepeat)
    }
}
#endif
