//
//  ScrollbackPayloadOwnershipTests.swift
//
//  Prepended history is parsed in a scratch terminal that owns its OSC 8
//  payload codes and releases them when it goes away. The prepended rows must
//  carry payloads the destination owns, so a code reissued later cannot
//  change or remove a link in history.
//
import Foundation
import Testing
@testable import SwiftTerm

final class ScrollbackPayloadOwnershipTests: TerminalDelegate {
    func send(source: Terminal, data: ArraySlice<UInt8>) {}

    private let esc = "\u{1b}"
    private let familyEmoji = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"

    private func makeTerminal() -> Terminal {
        let terminal = Terminal(delegate: self, options: TerminalOptions(cols: 40, rows: 4, scrollback: 100))
        terminal.feed(text: "live 0\r\nlive 1\r\nlive 2")
        return terminal
    }

    private func capture() -> String {
        "\(esc)]8;;https://a.example/\(esc)\\LINK\(esc)]8;;\(esc)\\ \(familyEmoji) " +
        "\(esc)[38;2;10;20;30mRGB\(esc)[0m \(esc)]8;;https://a.example/\(esc)\\AGAIN\(esc)]8;;\(esc)\\\r\n"
    }

    /// The payload value a live terminal stores for the same OSC 8 sequence.
    private func referencePayload() -> String? {
        let reference = Terminal(delegate: self, options: TerminalOptions(cols: 40, rows: 4))
        reference.feed(text: "\(esc)]8;;https://a.example/\(esc)\\X")
        return reference.buffer.lines[0][0].getPayload() as? String
    }

    /// Hands out and holds many fresh codes, so the oldest released codes
    /// (the scratch parser's) are reissued to unrelated values.
    private func churnAtomCodes() -> [TinyAtom] {
        (0..<64).compactMap { TinyAtom.lookup(value: "https://evil.example/\($0)") }
    }

    private func prependedRow(_ terminal: Terminal) -> BufferLine? {
        (0..<terminal.normalBuffer.lines.count)
            .map { terminal.normalBuffer.lines[$0] }
            .first { $0.translateToString(trimRight: true).hasPrefix("LINK") }
    }

    @Test func prependedLinkSurvivesScratchReleaseAndCodeReuse() throws {
        let expected = try #require(referencePayload())
        let terminal = makeTerminal()
        let inserted = terminal.prependScrollbackCapture(byteArray: ArraySlice(capture().utf8))
        #expect(inserted > 0)

        let reissued = churnAtomCodes()
        defer { reissued.forEach { $0.release() } }

        let row = try #require(prependedRow(terminal))
        #expect(row[0].getPayload() as? String == expected)
        #expect(row[3].getPayload() as? String == expected)
        // The codes the destination stores are ones it tracks: garbage
        // collection keeps them because history uses them.
        terminal.garbageCollectPayload()
        #expect(row[0].getPayload() as? String == expected)
    }

    @Test func repeatedSourcePayloadIsRemappedOnce() throws {
        let terminal = makeTerminal()
        terminal.prependScrollbackCapture(byteArray: ArraySlice(capture().utf8))
        let row = try #require(prependedRow(terminal))
        // Every cell of one link run carries the same source code; it maps to
        // one destination code. A second OSC 8 run of the same URL is a
        // distinct source code and keeps its own destination code.
        #expect(row[0].payload.code != 0)
        #expect((1..<4).allSatisfy { row[$0].payload.code == row[0].payload.code })
        let againStart = try #require((0..<row.count).first { $0 > 4 && row[$0].getCharacter() == "A" })
        #expect(row[againStart].payload.code != 0)
        #expect(row[againStart + 4].payload.code == row[againStart].payload.code)
    }

    @Test func prependKeepsGraphemeAndTruecolor() throws {
        let terminal = makeTerminal()
        terminal.prependScrollbackCapture(byteArray: ArraySlice(capture().utf8))
        let reissued = churnAtomCodes()
        defer { reissued.forEach { $0.release() } }

        let row = try #require(prependedRow(terminal))
        let text = row.translateToString(trimRight: true)
        #expect(text.contains(familyEmoji))
        let rCell = (0..<row.count).first { row[$0].getCharacter() == "R" && row[$0].attribute.fg != .defaultColor }
        let cell = try #require(rCell, "no colored R in \(text)")
        #expect(row[cell].attribute.fg == .trueColor(red: 10, green: 20, blue: 30))
        #expect(row[cell].payload.code == 0)
    }
}
