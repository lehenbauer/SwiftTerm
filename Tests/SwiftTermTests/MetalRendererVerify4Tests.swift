//
//  MetalRendererVerify4Tests.swift
//
//  Fork verification round 4, migrated to v1.99.2's renderer seams. A Kitty
//  put that fails validation only touches LRU bookkeeping, so the Metal frame
//  must reuse every cached row and stay identical. The fork's Kitty render
//  mutation generation no longer exists; the unchanged frame, row reuse and
//  empty update range are the observable contract.
//
#if os(macOS)
import AppKit
import Foundation
import Testing

@testable import SwiftTerm

@MainActor
@Suite(.serialized)
final class MetalRendererVerify4Tests {
    private static let rows = 12

    /// Rows the harness view actually shows (its frame sizes the grid).
    private func visibleRows(_ harness: MetalRowCacheTests.Harness) -> Int {
        harness.view.terminalDimensions.rows
    }

    private func kitty(_ control: String, payload: [UInt8]? = nil) -> String {
        if let payload {
            return "\u{1b}_G\(control);\(Data(payload).base64EncodedString())\u{1b}\\"
        }
        return "\u{1b}_G\(control)\u{1b}\\"
    }

    @Test(.enabled(if: MetalRowCacheTests.metalIsUsable, "needs Metal"))
    func rejectedKittyPutReusesCachedRowsWithoutChangingOutput() async throws {
        let harness = try #require(MetalRowCacheTests.Harness(cols: 40, rows: Self.rows))
        let view = harness.view
        view.feed(text: "stable renderer content")
        let pixels = Array(repeating: [UInt8](arrayLiteral: 255, 0, 0, 255), count: 4).flatMap { $0 }
        view.feed(text: kitty("a=t,f=32,s=2,v=2,t=d,i=42,q=2", payload: pixels))
        let before = try #require(await harness.frame())
        view.withTerminal { $0.clearUpdateRange() }

        // The image lookup updates only its LRU access tick before the invalid
        // parent makes display fail.
        view.feed(text: kitty("a=p,i=42,p=21,P=999,Q=999,q=2"))
        let (terminalDirty, placementsEmpty) = view.withTerminal { terminal in
            (terminal.getUpdateRange(), terminal.kittyGraphicsState.placementsByKey.isEmpty)
        }
        let after = try #require(await harness.frame())
        let truth = try #require(await harness.freshFrame())

        #expect(placementsEmpty)
        #expect(terminalDirty == nil)
        #expect(after.rows == before.rows)
        #expect(after.pixels == before.pixels)
        #expect(after.rebuilt == 0)
        #expect(after.cached == visibleRows(harness))
        #expect(after.pixels == truth.pixels)
    }

    @Test func defaultFontSetterStillSoftResetsTerminalModes() {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        view.resize(cols: 40, rows: Self.rows)
        view.feed(text: "\u{1b}[?1h\u{1b}[?6h\u{1b}[?25l\u{1b}[4h")
        let before = terminalModeSummary(view)

        view.font = NSFont.monospacedSystemFont(ofSize: view.font.pointSize, weight: .regular)
        let after = terminalModeSummary(view)

        #expect(before == "appCursor=true origin=true hidden=true insert=true")
        #expect(after == "appCursor=false origin=false hidden=false insert=false")
    }

    private func terminalModeSummary(_ view: TerminalView) -> String {
        view.withTerminal { terminal in
            "appCursor=\(terminal.applicationCursor) origin=\(terminal.originMode) " +
                "hidden=\(terminal.cursorHidden) insert=\(terminal.insertMode)"
        }
    }
}
#endif
