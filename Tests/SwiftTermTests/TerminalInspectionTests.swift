//
//  TerminalInspectionTests.swift
//  SwiftTermTests
//

import Foundation
import Testing
@testable import SwiftTerm

final class TerminalInspectionTests {
    private let esc = "\u{1b}"

    // MARK: - Basics

    @Test func testEmptyTerminalDimsAndStableHash() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 80, rows: 24)
        let a = terminal.inspect()
        let b = terminal.inspect()

        #expect(a.cols == 80)
        #expect(a.rows == 24)
        #expect(a.viewportText.count == 24)
        #expect(a.scrolledRows == 0)
        #expect(a.bufferKind == "normal")
        #expect(a.isAlternateScreen == false)
        #expect(a.isAlternateScreen == (a.bufferKind == "alt"))
        #expect(a.trimRight == true)
        #expect(a.contentHash == b.contentHash)
        #expect(a.modes.mouseMode == "off")
        #expect(a.modes.mouseProtocol == "x10")
        #expect(a.kittyKeyboard.active == false)
        #expect(a.kittyKeyboard.flags.isEmpty)
        #expect(a.kittyKeyboard.stackDepth == 0)
    }

    @Test func testAsciiViewportTextAndHashGolden() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 20, rows: 5)
        terminal.feed(text: "hello")
        let snap = terminal.inspect()

        #expect(snap.viewportText[0] == "hello")
        for r in 1..<5 {
            #expect(snap.viewportText[r] == "")
        }

        let expectedHash = Terminal.computeInspectionContentHash(
            trimRight: true,
            viewportText: snap.viewportText
        )
        #expect(snap.contentHash == expectedHash)

        // Pin a concrete golden for the "hello" + 4 blank rows case.
        let recomputed = TerminalInspectionHash.fnv1a64(data: Data(
            ("trimRight=1\nhello\n\n\n\n\n").utf8
        ))
        #expect(snap.contentHash == recomputed)
    }

    @Test func testTrimRightFlagChangesHash() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 10, rows: 2)
        terminal.feed(text: "ab")
        let trimmed = terminal.inspect(trimRight: true)
        let full = terminal.inspect(trimRight: false)
        #expect(trimmed.trimRight == true)
        #expect(full.trimRight == false)
        #expect(trimmed.contentHash != full.contentHash)
        #expect(full.viewportText[0].count == 10)
    }

    // MARK: - Cursor

    @Test func testPendingWrapCursorProjection() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 5, rows: 3)
        terminal.feed(text: "12345")
        #expect(terminal.buffer.x == 5)

        let snap = terminal.inspect()
        #expect(snap.cursorEngineCol == 5)
        #expect(snap.cursorEngineRow == 0)
        #expect(snap.cursorPendingWrap == true)
        #expect(snap.cursorViewportCol == 4)
        #expect(snap.cursorViewportRow == 0)
        #expect(snap.cursorOnScreen == true)
    }

    // MARK: - Scroll

    @Test func testScrolledRowsFormula() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 20, rows: 4, scrollback: 100)
        for i in 0..<20 {
            terminal.feed(text: "line\(i)\n")
        }
        #expect(terminal.buffer.yBase > 0)
        #expect(terminal.buffer.yDisp == terminal.buffer.yBase)

        let live = terminal.inspect()
        #expect(live.scrolledRows == 0)
        #expect(live.scrolledRows == terminal.buffer.yBase - terminal.buffer.yDisp)

        // Scroll viewport up by 2 rows if possible.
        let targetDisp = max(0, terminal.buffer.yBase - 2)
        terminal.buffer.yDisp = targetDisp
        let scrolled = terminal.inspect()
        #expect(scrolled.scrolledRows == terminal.buffer.yBase - terminal.buffer.yDisp)
        #expect(scrolled.scrolledRows == 2 || scrolled.scrolledRows == terminal.buffer.yBase)
    }

    // MARK: - Alt screen + kitty

    @Test func testAltScreenInvariantAndKittyIndependence() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 20, rows: 10)

        terminal.feed(text: "\(esc)[=1;1u")
        var snap = terminal.inspect()
        #expect(snap.kittyKeyboard.active == true)
        #expect(snap.kittyKeyboard.flags == ["disambiguate"])
        #expect(snap.kittyKeyboard.buffer == "normal")
        #expect(snap.kittyKeyboard.otherBufferFlagsRaw == 0)

        terminal.feed(text: "\(esc)[?1049h")
        snap = terminal.inspect()
        #expect(snap.isAlternateScreen == true)
        #expect(snap.bufferKind == "alt")
        #expect(snap.isAlternateScreen == (snap.bufferKind == "alt"))
        #expect(snap.kittyKeyboard.active == false)
        #expect(snap.kittyKeyboard.buffer == "alt")
        #expect(snap.kittyKeyboard.otherBufferFlagsRaw == KittyKeyboardFlags.disambiguate.rawValue)

        terminal.feed(text: "\(esc)[=8;1u")
        snap = terminal.inspect()
        #expect(snap.kittyKeyboard.flags == ["reportAllKeys"])
        #expect(snap.kittyKeyboard.otherBufferFlagsRaw == KittyKeyboardFlags.disambiguate.rawValue)
    }

    @Test func testKittyPushPopStackDepth() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 20, rows: 10)
        terminal.feed(text: "\(esc)[>1u")
        var snap = terminal.inspect()
        #expect(snap.kittyKeyboard.stackDepth == 1)
        #expect(snap.kittyKeyboard.flags == ["disambiguate"])

        terminal.feed(text: "\(esc)[>8u")
        snap = terminal.inspect()
        #expect(snap.kittyKeyboard.stackDepth == 2)
        #expect(snap.kittyKeyboard.flags == ["reportAllKeys"])

        terminal.feed(text: "\(esc)[<u")
        snap = terminal.inspect()
        #expect(snap.kittyKeyboard.stackDepth == 1)
        #expect(snap.kittyKeyboard.flags == ["disambiguate"])
    }

    @Test func testSoftResetPreservesKittyFullResetClears() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 20, rows: 10)
        terminal.feed(text: "\(esc)[=1;1u")
        terminal.feed(text: "\(esc)[>8u")
        #expect(terminal.inspect().kittyKeyboard.active == true)

        terminal.softReset()
        let afterSoft = terminal.inspect()
        #expect(afterSoft.kittyKeyboard.active == true)
        #expect(afterSoft.kittyKeyboard.stackDepth == 1)

        terminal.resetToInitialState()
        let afterFull = terminal.inspect()
        #expect(afterFull.kittyKeyboard.active == false)
        #expect(afterFull.kittyKeyboard.flags.isEmpty)
        #expect(afterFull.kittyKeyboard.stackDepth == 0)
    }

    // MARK: - Modes

    @Test func testSynchronizedOutputFlag() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 20, rows: 5)
        terminal.feed(text: "\(esc)[?2026h")
        #expect(terminal.inspect().modes.synchronizedOutputActive == true)
        terminal.feed(text: "\(esc)[?2026l")
        #expect(terminal.inspect().modes.synchronizedOutputActive == false)
    }

    @Test func testMouseModeAndProtocolWireNames() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 20, rows: 5)
        // Enable any-event mouse tracking (DECSET 1003) and SGR (1006).
        terminal.feed(text: "\(esc)[?1003h")
        terminal.feed(text: "\(esc)[?1006h")
        let snap = terminal.inspect()
        #expect(snap.modes.mouseMode == "anyEvent")
        #expect(snap.modes.mouseProtocol == "sgr")
    }

    // MARK: - Codable

    @Test func testCodableSnakeCaseAndContentHashString() throws {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 10, rows: 3)
        terminal.feed(text: "xy")
        let snap = terminal.inspect()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snap)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj?["cursor_engine_col"] != nil)
        #expect(obj?["kitty_keyboard"] != nil)
        #expect(obj?["content_hash"] is String)
        #expect(obj?["content_hash"] as? String == String(snap.contentHash))
        #expect(obj?["viewport_text"] is [Any])

        // UInt64.max must survive as decimal string.
        var maxSnap = snap
        maxSnap.contentHash = UInt64.max
        let maxData = try encoder.encode(maxSnap)
        let maxObj = try JSONSerialization.jsonObject(with: maxData) as? [String: Any]
        #expect(maxObj?["content_hash"] as? String == "18446744073709551615")

        let decoded = try JSONDecoder().decode(TerminalInspectionSnapshot.self, from: data)
        #expect(decoded == snap)
    }

    @Test func testFnvMatchesIndependentImplementation() {
        // Empty single-row trimRight=1 → "trimRight=1\n\n"
        let hash = Terminal.computeInspectionContentHash(trimRight: true, viewportText: [""])
        var expected: UInt64 = 14_695_981_039_346_656_037
        let prime: UInt64 = 1_099_511_628_211
        for byte in Array("trimRight=1\n\n".utf8) {
            expected ^= UInt64(byte)
            expected = expected &* prime
        }
        #expect(hash == expected)
    }
}
