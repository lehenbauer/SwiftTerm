#if os(iOS) || os(visionOS)
import UIKit
import XCTest
@testable import SwiftTerm

/// Drive the legacy (no Kitty flags) functional-key path of `pressesBegan`
/// with synthetic hardware presses, then check the repeat timer's bytes,
/// its cancellation, and that it does not keep the view alive.
@MainActor
final class IOSLegacyKeyRepeatTests: XCTestCase {
    private final class FakeKey: UIKey {
        private let code: UIKeyboardHIDUsage
        init(code: UIKeyboardHIDUsage) {
            self.code = code
            super.init()
        }
        required init?(coder: NSCoder) { nil }
        override var keyCode: UIKeyboardHIDUsage { code }
        override var characters: String { "" }
        override var charactersIgnoringModifiers: String { "" }
        override var modifierFlags: UIKeyModifierFlags { [] }
    }

    private final class FakePress: UIPress {
        private let fakeKey: UIKey
        init(key: UIKey) {
            fakeKey = key
            super.init()
        }
        override var key: UIKey? { fakeKey }
    }

    private final class ObservedView: TerminalView {
        var label = ""
        deinit {
            print("[IOSLegacyKeyRepeat] deinit view=\(label)")
        }
    }

    private final class ByteRecorder: TerminalViewDelegate {
        var sends: [[UInt8]] = []
        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            sends.append(Array(data))
            print("[IOSLegacyKeyRepeat] send #\(sends.count) bytes=\(Array(data)) timer=\(source.keyRepeat != nil)")
        }
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func scrolled(source: TerminalView, position: Double) {}
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }

    private static let downArrow: [UInt8] = [0x1b, 0x5b, 0x42]

    private func makeView(_ label: String) -> ObservedView {
        let view = ObservedView(
            frame: CGRect(x: 0, y: 0, width: 400, height: 300), font: nil,
            terminalOptions: TerminalOptions(cols: 40, rows: 10, scrollback: 100),
            initialGeometry: .grid(cols: 40, rows: 10), autoResizeGrid: false
        )
        view.label = label
        XCTAssertTrue(view.terminal.keyboardEnhancementFlags.isEmpty)
        return view
    }

    private func spin(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds))
    }

    /// Let queued `DispatchQueue.main.async { self... }` work (e.g. the
    /// sizeChanged notification) release the view, well before the 0.4s
    /// initial repeat delay.
    private func drainMainQueue() {
        spin(0.05)
    }

    func testLegacyArrowRepeatsAndStopsOnPressEnded() {
        let view = makeView("bytes")
        let recorder = ByteRecorder()
        view.terminalDelegate = recorder
        let press = FakePress(key: FakeKey(code: .keyboardDownArrow))

        print("[IOSLegacyKeyRepeat] pressesBegan down")
        view.pressesBegan([press], with: nil)
        XCTAssertEqual(recorder.sends, [Self.downArrow])
        XCTAssertNotNil(view.keyRepeat)

        // Initial delay 0.4s, then 0.1s interval.
        spin(0.75)
        let afterRepeat = recorder.sends.count
        print("[IOSLegacyKeyRepeat] after spin sends=\(afterRepeat)")
        XCTAssertGreaterThanOrEqual(afterRepeat, 3)
        XCTAssertTrue(recorder.sends.allSatisfy { $0 == Self.downArrow })

        print("[IOSLegacyKeyRepeat] pressesEnded down")
        view.pressesEnded([press], with: nil)
        XCTAssertNil(view.keyRepeat)
        let afterEnd = recorder.sends.count
        spin(0.5)
        XCTAssertEqual(recorder.sends.count, afterEnd)
    }

    func testUnattachedViewWithoutKeyPressDeallocates() {
        weak var weakView: ObservedView?
        autoreleasepool {
            let view = makeView("control")
            weakView = view
            // CADisplayLink retains its target until the host's teardown call.
            view.updateUiClosed()
        }
        drainMainQueue()
        print("[IOSLegacyKeyRepeat] control released alive=\(weakView != nil)")
        XCTAssertNil(weakView)
    }

    func testPendingLegacyArrowRepeatDoesNotRetainView() {
        let recorder = ByteRecorder()
        weak var weakView: ObservedView?
        weak var weakTimer: Timer?
        defer {
            // The run loop owns the timer; stop it so no test run leaves it firing.
            weakTimer?.invalidate()
        }
        autoreleasepool {
            let view = makeView("pressed")
            view.terminalDelegate = recorder
            weakView = view
            print("[IOSLegacyKeyRepeat] pressesBegan down (no end)")
            view.pressesBegan([FakePress(key: FakeKey(code: .keyboardDownArrow))], with: nil)
            XCTAssertNotNil(view.keyRepeat)
            weakTimer = view.keyRepeat
            view.updateUiClosed()
        }
        drainMainQueue()
        print("[IOSLegacyKeyRepeat] pressed released alive=\(weakView != nil) timerValid=\(weakTimer?.isValid ?? false)")
        XCTAssertEqual(recorder.sends, [Self.downArrow])
        XCTAssertNil(weakView, "pending key-repeat timer retained the view")
        if let leaked = weakView {
            // Release the timer so a failing run does not keep firing.
            leaked.keyRepeat?.invalidate()
            leaked.keyRepeat = nil
        }
        weakView = nil
        // A released view's timer must not fire after dealloc.
        spin(0.6)
        XCTAssertEqual(recorder.sends, [Self.downArrow])
    }
}
#endif
