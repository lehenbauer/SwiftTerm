#if os(macOS) || os(iOS) || os(visionOS)
import Foundation
import Testing
@testable import SwiftTerm

@MainActor
@Suite(.serialized)
struct MirrorHostPolicyTests {
    /// Models a host's reply/mouse callback filter. Paste must bypass it by
    /// provenance, including a payload that happens to look like mouse bytes.
    private final class ReplyFilteringView: TerminalView {
        nonisolated override func send(source: Terminal, data: ArraySlice<UInt8>) {}
    }
    final class Recorder: TerminalViewDelegate {
        var sent: [UInt8] = []
        var sizeChanges = 0
        var clipboardReads = 0
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) { sizeChanges += 1 }
        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func send(source: TerminalView, data: ArraySlice<UInt8>) { sent.append(contentsOf: data) }
        func scrolled(source: TerminalView, position: Double) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
        // Required by the UIKit delegate; AppKit's has a default.
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
        func clipboardRead(source: TerminalView) -> Data? {
            clipboardReads += 1
            return Data("clipboard".utf8)
        }
    }

    private func makeView() -> TerminalView {
        TerminalView(frame: CGRect(x: 0, y: 0, width: 640, height: 320))
    }

    private func drain() async {
        for _ in 0..<4 {
            await withCheckedContinuation { c in DispatchQueue.main.async { c.resume() } }
        }
    }

    @Test func viewPasteBypassesReplyFilterWithoutReenteringTerminalLock() async {
        let view = ReplyFilteringView(frame: CGRect(x: 0, y: 0, width: 640, height: 320))
        let recorder = Recorder()
        view.terminalDelegate = recorder
        view.configureForTmuxMirror()
        for bracketed in [false, true] {
            view.feed(text: bracketed ? "\u{1b}[?2004h" : "\u{1b}[?2004l")
            for text in ["plain paste", "\u{1b}[<0;3;4M"] {
                recorder.sent = []
                view.pasteText(text)
                await drain()
                // The upstream paste safety policy replaces ESC with a space.
                let sanitized = text.replacingOccurrences(of: "\u{1b}", with: " ")
                let expected = bracketed ? "\u{1b}[200~" + sanitized + "\u{1b}[201~" : sanitized
                #expect(recorder.sent == Array(expected.utf8))
            }
        }
        recorder.sent = []
        let mouseLookingInput = Array("\u{1b}[<0;3;4M".utf8)
        view.withTerminal { $0.sendUserInput(mouseLookingInput[...]) }
        await drain()
        #expect(recorder.sent == mouseLookingInput)
    }

    @Test func pasteAndFollowingInputKeepSubmissionOrder() async {
        let view = ReplyFilteringView(frame: CGRect(x: 0, y: 0, width: 640, height: 320))
        let recorder = Recorder()
        view.terminalDelegate = recorder
        view.configureForTmuxMirror()
        view.pasteText("paste")
        view.send(data: Array("\r".utf8)[...])
        await drain()
        #expect(recorder.sent == Array("paste\r".utf8))
    }

    #if os(iOS) || os(visionOS)
    @Test func mirrorKeepsProgramPanDisabledAcrossEveryRefreshEntryPoint() async {
        for lateConfiguration in [false, true] {
            let view = makeView()
            if !lateConfiguration { view.configureForTmuxMirror() }
            view.feed(text: "\u{1b}[?1049h")
            await drain()
            if lateConfiguration {
                #expect(view.panMouseGesture != nil) // Ordinary upstream control.
                view.configureForTmuxMirror()
            }
            #expect(view.panMouseGesture == nil)
            #expect(view.panGestureRecognizer.minimumNumberOfTouches == 1)
            view.feed(text: "\u{1b}[?1049l\u{1b}[?1000h")
            await drain()
            view.allowMouseReporting = false
            view.allowMouseReporting = true
            #expect(view.panMouseGesture == nil)
            #expect(view.panGestureRecognizer.minimumNumberOfTouches == 1)
        }
    }
    #endif

    @Test func repliesAreSuppressedButUserBytesAndMouseSurvive() async {
        let view = makeView(), recorder = Recorder()
        view.terminalDelegate = recorder
        view.configureForTmuxMirror()
        // DA1, DSR, OSC color, XTGETTCAP, DECRQM, OSC52, focus enable.
        let queries = "\u{1b}[c\u{1b}[6n\u{1b}]11;?\u{7}" +
            "\u{1b}P+q544e\u{1b}\\\u{1b}[?1004$p\u{1b}]52;c;?\u{7}\u{1b}[?1004h"
        view.feed(text: queries)
        await drain()
        #expect(recorder.sent.isEmpty)
        #expect(recorder.clipboardReads == 0)
        // Reset must not turn the mirror back into a responding emulator.
        view.feed(text: "\u{1b}c\u{1b}[!p" + queries)
        await drain()
        #expect(recorder.sent.isEmpty)
        view.send(data: [UInt8(ascii: "k")][...])
        await drain()
        #expect(recorder.sent == Array("k".utf8))
        recorder.sent = []
        view.feed(text: "\u{1b}[?1000h\u{1b}[?1006h")
        view.withTerminal { $0.sendEvent(buttonFlags: 0, x: 2, y: 3) }
        await drain()
        #expect(recorder.sent == Array("\u{1b}[<0;3;4M".utf8))
    }

    @Test func ordinaryClipboardReplyUsesResponsePathAndLateMirrorConfigurationSuppressesIt() async {
        let view = makeView(), recorder = Recorder()
        view.terminalDelegate = recorder
        view.feed(text: "\u{1b}]52;c;?\u{7}")
        await drain()
        #expect(recorder.clipboardReads == 1)
        #expect(recorder.sent == Array("\u{1b}]52;c;Y2xpcGJvYXJk\u{1b}\\".utf8))
        recorder.sent = []
        view.feed(text: "\u{1b}]52;c;?\u{7}")
        view.configureForTmuxMirror()
        await drain()
        #expect(recorder.sent.isEmpty)
    }

    @Test func mirrorFocusReportsOnlyRealChangesWhenOptedIn() async {
        let view = makeView(), recorder = Recorder()
        view.terminalDelegate = recorder
        view.configureForTmuxMirror(reportUserFocusChanges: true)
        view.feed(text: "\u{1b}[?1004h")
        await drain()
        #expect(recorder.sent.isEmpty)
        view.withTerminal { $0.setTerminalFocus(false) }
        await drain()
        #expect(recorder.sent == Array("\u{1b}[O".utf8))
        recorder.sent = []
        view.configureForTmuxMirror(reportUserFocusChanges: false)
        view.withTerminal { $0.setTerminalFocus(true) }
        await drain()
        #expect(recorder.sent.isEmpty)
    }

    @Test func mirrorKeepsChangedSelectionAndRespectsUserClear() {
        for mirror in [false, true] {
            let view = makeView()
            if mirror { view.configureForTmuxMirror() }
            view.feed(text: "spinner")
            view.withTerminal { _ in
                view.selection.setSelection(start: Position(col: 0, row: 0), end: Position(col: 7, row: 0))
            }
            view.feed(text: "\rchanged")
            #expect(view.selectionActive == mirror)
            view.selectNone()
            view.feed(text: "\ragain")
            #expect(!view.selectionActive)
        }
    }

    @Test func ordinarySelectionSurvivesChangesOutsideItsCells() {
        let view = makeView()
        view.feed(text: "selected elsewhere")
        view.withTerminal { _ in
            view.selection.setSelection(start: Position(col: 0, row: 0), end: Position(col: 8, row: 0))
        }
        view.feed(text: "\u{1b}[2;1Hother row")
        #expect(view.selectionActive)
        #expect(view.getSelection() == "selected")
    }

    @Test func cursorPreferencePreservesApplicationStyleInCaretAndSnapshot() async {
        let view = makeView()
        view.cursorBlinkEnabled = false
        view.feed(text: "\u{1b}[5 q")
        await drain()
        #expect(view.terminalStateSnapshot().cursorStyle == .blinkBar)
        #expect(view.caretView?.style == .steadyBar)
        _ = view.renderOwner.prepareFrame(viewState: FrameViewState(view: view))
        view.renderOwner.withSnapshotForDrawing(viewState: FrameViewState(view: view)) { snapshot, _ in
            #expect(snapshot.cursorStyle == .steadyBar)
        }
        view.cursorBlinkEnabled = true
        #expect(view.caretView?.style == .blinkBar)
        view.cursorStyleOverride = .steadyBlock
        #expect(view.terminalStateSnapshot().cursorStyle == .blinkBar)
        _ = view.renderOwner.prepareFrame(viewState: FrameViewState(view: view))
        view.renderOwner.withSnapshotForDrawing(viewState: FrameViewState(view: view)) { snapshot, _ in
            #expect(snapshot.cursorStyle == .steadyBlock)
        }
    }

    @Test func queuedPixelResizeCannotOverrideFixedGridOrExplicitPin() {
        let view = makeView(), recorder = Recorder()
        view.terminalDelegate = recorder
        view.autoResizeGrid = false
        view.resize(cols: 100, rows: 30, preservingTerminalModes: true)
        recorder.sizeChanges = 0
        view.queueSizeChange(newSize: CGSize(width: 320, height: 100))
        let frame = view.renderOwner.prepareFrame(viewState: FrameViewState(view: view))
        #expect(view.terminalDimensions.cols == 100 && view.terminalDimensions.rows == 30)
        #expect(frame?.resizedTo == nil)
        #expect(recorder.sizeChanges == 0)
        view.autoResizeGrid = true
        view.queueSizeChange(newSize: CGSize(width: 320, height: 100))
        view.resize(cols: 120, rows: 40, preservingTerminalModes: true)
        _ = view.renderOwner.prepareFrame(viewState: FrameViewState(view: view))
        #expect(view.terminalDimensions.cols == 120 && view.terminalDimensions.rows == 40)
        view.queueSizeChange(newSize: CGSize(width: 320, height: 100))
        view.autoResizeGrid = false
        view.autoResizeGrid = true
        _ = view.renderOwner.prepareFrame(viewState: FrameViewState(view: view))
        #expect(view.terminalDimensions.cols == 120 && view.terminalDimensions.rows == 40)
        // A new request remains effective for ordinary views.
        view.queueSizeChange(newSize: CGSize(width: 320, height: 100))
        _ = view.renderOwner.prepareFrame(viewState: FrameViewState(view: view))
        #expect(view.terminalDimensions.cols != 120 && view.terminalDimensions.rows != 40)
    }

    @Test func alreadyConsumedResizeRequestCannotOverrideNewerPin() throws {
        let view = makeView()
        view.queueSizeChange(newSize: CGSize(width: 320, height: 100))
        // A render thread can already own this value when the main thread
        // pins a newer grid. Clearing the mailbox cannot revoke this copy.
        let oldRequest = try #require(view.renderOwner.mailbox.takeRequest(viewState: FrameViewState(view: view)))
        #expect(oldRequest.pendingSize != nil)
        view.resize(cols: 120, rows: 40, preservingTerminalModes: true)
        let result = view.renderOwner.prepareFrame(oldRequest)
        #expect(result?.resizedTo == nil)
        #expect(view.terminalDimensions.cols == 120 && view.terminalDimensions.rows == 40)
    }
}
#endif
