//
//  MetalRendererRedTeamRound3Tests.swift
//
//  Fork red-team round 3, migrated to v1.99.2's renderer seams: Kitty
//  placement and payload changes, selection, cursor moves and recycled lines
//  must leave the incremental Metal frame equal to a from-scratch rebuild
//  (`MetalRowCacheTests.Harness`). The fork's Kitty mutation stamp and
//  line-info invalidation table no longer exist; their observable effects are
//  asserted instead.
//
#if os(macOS)
import AppKit
import Foundation
import Testing

@testable import SwiftTerm

@MainActor
@Suite(.serialized)
final class MetalRendererRedTeamRound3Tests {
    private static let rows = 12

    /// Rows the harness view actually shows (its frame sizes the grid).
    private func visibleRows(_ harness: MetalRowCacheTests.Harness) -> Int {
        harness.view.terminalDimensions.rows
    }

    private func makeHarness(scrollback: Int = 200) throws -> MetalRowCacheTests.Harness {
        try #require(MetalRowCacheTests.Harness(cols: 40, rows: 12, scrollback: scrollback))
    }

    private func optimizedAndTruth(_ harness: MetalRowCacheTests.Harness) async throws
        -> (MetalRowCacheTests.DrawnFrame, MetalRowCacheTests.DrawnFrame)
    {
        let optimized = try #require(await harness.frame())
        let truth = try #require(await harness.freshFrame())
        return (optimized, truth)
    }

    private func kitty(_ control: String, payload: [UInt8]? = nil) -> String {
        if let payload {
            return "\u{1b}_G\(control);\(Data(payload).base64EncodedString())\u{1b}\\"
        }
        return "\u{1b}_G\(control)\u{1b}\\"
    }

    private func placeholder(imageId: UInt32, placementId: UInt32) -> String {
        precondition(imageId < 256 && placementId < 256)
        return "\u{1b}[38;5;\(imageId)m\u{1b}[58;5;\(placementId)m\u{10EEEE}\u{0305}\u{0305}"
    }

    @Test(.enabled(if: MetalRowCacheTests.metalIsUsable, "needs Metal"))
    func replacingVirtualPlacementInPlaceInvalidatesCachedRows() async throws {
        let harness = try makeHarness()
        let view = harness.view
        let imageId: UInt32 = 42
        let placementId: UInt32 = 21
        let pixels = Array(repeating: [UInt8](arrayLiteral: 255, 0, 0, 255), count: 4).flatMap { $0 }

        view.feed(text: kitty("a=T,f=32,s=2,v=2,t=d,c=1,r=1,i=\(imageId),p=\(placementId),U=1", payload: pixels))
        view.feed(text: placeholder(imageId: imageId, placementId: placementId))
        let before = try #require(await harness.frame())
        let beforeLineGeneration = view.withTerminal { $0.displayBuffer.lines[0].generation }

        view.feed(text: kitty("a=p,i=\(imageId),p=\(placementId),U=1,c=2,r=1"))
        let afterLineGeneration = view.withTerminal { $0.displayBuffer.lines[0].generation }
        let (optimized, truth) = try await optimizedAndTruth(harness)

        // The placeholder row's text did not change; only the placement did.
        #expect(beforeLineGeneration == afterLineGeneration)
        #expect(optimized.pixels != before.pixels, "control: the wider placement must draw differently")
        #expect(optimized.rows == truth.rows)
        #expect(optimized.pixels == truth.pixels)
    }

    @Test(.enabled(if: MetalRowCacheTests.metalIsUsable, "needs Metal"))
    func kittyPayloadTailChangeInvalidatesSnapshotAndTextureCache() async throws {
        let harness = try makeHarness()
        let view = harness.view
        let imageId: UInt32 = 42
        let placementId: UInt32 = 21
        // Opaque green, so the drawn image is distinguishable from the
        // background; the changed tail byte turns one pixel yellow.
        var original = Array(repeating: UInt8(0), count: 5 * 4 * 4)
        for pixel in stride(from: 0, to: original.count, by: 4) {
            original[pixel + 1] = 255
            original[pixel + 3] = 255
        }

        view.feed(text: kitty("a=T,f=32,s=5,v=4,t=d,c=1,r=1,i=\(imageId),p=\(placementId),U=1", payload: original))
        view.feed(text: placeholder(imageId: imageId, placementId: placementId))
        let before = try #require(await harness.frame())

        var replacement = original
        replacement[68] = 255
        // Same-id retransmit replaces the image and removes its placements
        // (kitty graphics protocol; adjudication 8). The frame losing the
        // image proves it was actually drawn before.
        view.feed(text: kitty("a=t,f=32,s=5,v=4,t=d,i=\(imageId)", payload: replacement))
        let withoutPlacement = try #require(await harness.frame())
        #expect(withoutPlacement.pixels != before.pixels, "control: the image must have been drawn before")

        let storedTailChanged = view.withTerminal { terminal -> Bool in
            guard let image = terminal.kittyGraphicsState.imagesById[imageId],
                  case .rgba(let bytes, _, _) = image.payload else { return false }
            return bytes[68] == 255
        }
        view.feed(text: kitty("a=p,i=\(imageId),p=\(placementId),U=1,c=1,r=1"))
        let (optimized, truth) = try await optimizedAndTruth(harness)

        #expect(storedTailChanged)
        #expect(optimized.pixels != before.pixels, "a changed payload tail must reach the texture")
        #expect(optimized.pixels != withoutPlacement.pixels, "the re-placed image must draw")
        #expect(optimized.rows == truth.rows)
        #expect(optimized.pixels == truth.pixels)
    }

    @Test func resetFontSizePreservesTerminalModesAndClearsSelection() async throws {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        view.resize(cols: 40, rows: Self.rows)
        view.font = NSFont.monospacedSystemFont(ofSize: 24, weight: .regular)
        view.feed(text: "mode preservation probe")
        view.feed(text: "\u{1b}[?1h\u{1b}[?6h\u{1b}[?25l\u{1b}[4h")
        view.withTerminal { _ in
            view.selection.setSelection(start: Position(col: 0, row: 0), end: Position(col: 4, row: 0))
        }

        let before = terminalModeSummary(view)
        view.resetFontSize()
        let after = terminalModeSummary(view)

        #expect(before == "appCursor=true origin=true hidden=true insert=true selection=true")
        #expect(after == "appCursor=true origin=true hidden=true insert=true selection=false")
    }

    @Test(.enabled(if: MetalRowCacheTests.metalIsUsable, "needs Metal"))
    func deselectionRebuildsPreviouslyHighlightedRows() async throws {
        let harness = try makeHarness()
        let view = harness.view
        view.feed(text: String(repeating: "selection repaint row\r\n", count: 30))
        _ = try #require(await harness.frame())

        view.withTerminal { terminal in
            let yDisp = terminal.displayBuffer.yDisp
            view.selection.setSelection(start: Position(col: 1, row: yDisp + 2),
                                        end: Position(col: 10, row: yDisp + 4))
        }
        let selected = try #require(await harness.frame())

        view.selectNone()
        let (deselected, truth) = try await optimizedAndTruth(harness)

        #expect(selected.pixels != deselected.pixels)
        // Exactly the three formerly selected rows rebuild (adjudication 9).
        #expect(deselected.rebuilt == 3)
        #expect(deselected.cached == visibleRows(harness) - 3)
        #expect(!view.selectionActive)
        #expect(deselected.rows == truth.rows)
        #expect(deselected.pixels == truth.pixels)
    }

    @Test(.enabled(if: MetalRowCacheTests.metalIsUsable, "needs Metal"))
    func cursorMoveRebuildsCursorButReusesUnderlyingRows() async throws {
        let harness = try makeHarness()
        let view = harness.view
        view.feed(text: "cursor under-cell probe")
        let before = try #require(await harness.frame())

        view.feed(text: "\u{1b}[5D")
        let (moved, truth) = try await optimizedAndTruth(harness)

        #expect(before.rows == moved.rows, "cell rows must be reused across a cursor-only move")
        #expect(before.pixels != moved.pixels, "the cursor must move on screen")
        #expect(moved.rebuilt == 0)
        #expect(moved.cached == visibleRows(harness))
        #expect(moved.pixels == truth.pixels)
    }

    @Test(.enabled(if: MetalRowCacheTests.metalIsUsable, "needs Metal"))
    func recycledBufferLineIdentityCannotHitStaleGeneration() async throws {
        let harness = try makeHarness(scrollback: 0)
        let view = harness.view
        view.feed(text: String(repeating: "capacity recycle row\r\n", count: 20))
        _ = try #require(await harness.frame())

        let (recycledLine, generationBefore) = view.withTerminal { terminal in
            (terminal.displayBuffer.lines[0], terminal.displayBuffer.lines[0].generation)
        }

        view.feed(text: "identity recycle trigger\r\n")
        let (identityReused, generationAfter) = view.withTerminal { terminal in
            let buffer = terminal.displayBuffer
            return (buffer.lines[buffer.lines.count - 1] === recycledLine, recycledLine.generation)
        }
        let (optimized, truth) = try await optimizedAndTruth(harness)

        #expect(identityReused)
        #expect(generationAfter > generationBefore)
        #expect(optimized.rows == truth.rows)
        #expect(optimized.pixels == truth.pixels)
    }

    private func terminalModeSummary(_ view: TerminalView) -> String {
        let modes = view.withTerminal { terminal in
            "appCursor=\(terminal.applicationCursor) origin=\(terminal.originMode) " +
                "hidden=\(terminal.cursorHidden) insert=\(terminal.insertMode) "
        }
        return modes + "selection=\(view.selectionActive)"
    }
}
#endif
