//
//  FullDisplayRefreshTests.swift
//
//  `requestFullDisplayRefresh()` is the rehost/focus repaint command (P5): it
//  must repaint unchanged content, which a plain `requestRedraw()` (a frame
//  request only) does not. CG is observed through invalidation rects at the
//  frame tick. Metal is observed through completed renderer passes into an
//  offscreen-window surface; that is a GPU render, not proof of on-screen
//  presentation.
//
#if os(macOS)
import AppKit
import Metal
import Testing
@testable import SwiftTerm

private final class RefreshCapturingView: TerminalView {
    var invalidated: [NSRect] = []

    override func setNeedsDisplay(_ invalidRect: NSRect) {
        invalidated.append(invalidRect)
        super.setNeedsDisplay(invalidRect)
    }
}

@MainActor
@Suite(.serialized)
struct FullDisplayRefreshTests {
    private func fullFrameInvalidated(_ view: RefreshCapturingView) -> Bool {
        view.invalidated.contains { $0.width >= view.frame.width && $0.height >= view.frame.height }
    }

    private func settledView() -> RefreshCapturingView {
        let view = RefreshCapturingView(frame: CGRect(x: 0, y: 0, width: 640, height: 320))
        let rows = view.terminalDimensions.rows
        for i in 0..<(rows * 3) {
            view.feed(text: "line \(i)\r\n")
        }
        view.frameTick()
        view.withTerminal { $0.clearUpdateRange() }
        view.invalidated.removeAll()
        return view
    }

    @Test func unchangedContentRepaintsOnlyWhenRequested() {
        let view = settledView()

        view.requestRedraw()
        view.frameTick()
        #expect(view.invalidated.isEmpty, "control: a frame request alone repaints nothing unchanged")

        view.requestFullDisplayRefresh()
        view.frameTick()
        #expect(fullFrameInvalidated(view), "invalidated \(view.invalidated)")
    }

    @Test func fullRefreshRepaintsWhileScrolledBack() {
        let view = settledView()
        view.scrollTo(row: 0)
        view.frameTick()
        view.withTerminal { $0.clearUpdateRange() }
        view.invalidated.removeAll()
        #expect(view.withTerminal { $0.buffer.yBase - $0.buffer.yDisp } > 0)

        view.requestFullDisplayRefresh()
        view.frameTick()
        #expect(fullFrameInvalidated(view), "invalidated \(view.invalidated)")
    }

    /// A rehost: Metal enabled on a settled view, whose content does not
    /// change, then a full refresh must produce a completed render pass.
    @Test(.enabled(if: MetalRowCacheTests.metalIsUsable, "needs Metal"))
    func metalRehostRendersUnchangedContent() async throws {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 640, height: 320))
        let window = NSWindow(contentRect: CGRect(x: -10_000, y: -10_000, width: 640, height: 320),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        defer { window.contentView = nil }
        view.feed(text: "unchanged content\r\nsecond row")
        try view.setUseMetal(true)
        defer { try? view.setUseMetal(false) }
        // Let the first frames after the surface change finish.
        for _ in 0..<5 {
            view.frameTick()
            try await Task.sleep(for: .milliseconds(20))
        }

        view.resetDiagnostics()
        view.requestFullDisplayRefresh()
        view.frameTick()
        var renders = 0
        for _ in 0..<50 where renders == 0 {
            try await Task.sleep(for: .milliseconds(10))
            renders = view.diagnostics.renders
        }
        #expect(renders > 0, "no completed Metal render after a full refresh of unchanged content")
    }
}
#endif
