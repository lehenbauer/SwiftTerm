#if os(macOS) || os(iOS) || os(visionOS)
import Foundation
import Testing
@testable import SwiftTerm

@MainActor
@Suite(.serialized)
struct InteractiveEchoDisplayTests {
    private func drain() async {
        for _ in 0..<4 {
            await withCheckedContinuation { c in DispatchQueue.main.async { c.resume() } }
        }
    }

    @Test func windowBoundariesAndSynchronizedOutput() {
        let owner = TerminalRenderOwner()
        let start: UInt64 = 1_000_000_000
        #expect(!owner.shouldDisplayImmediatelyAfterUserInput(synchronizedOutputActive: false, now: start))
        owner.recordUserInputForDisplay(at: start)
        #expect(!owner.shouldDisplayImmediatelyAfterUserInput(synchronizedOutputActive: false, now: start - 1))
        #expect(owner.shouldDisplayImmediatelyAfterUserInput(synchronizedOutputActive: false, now: start))
        #expect(owner.shouldDisplayImmediatelyAfterUserInput(synchronizedOutputActive: false, now: start + 150_000_000))
        #expect(!owner.shouldDisplayImmediatelyAfterUserInput(synchronizedOutputActive: false, now: start + 150_000_001))
        #expect(!owner.shouldDisplayImmediatelyAfterUserInput(synchronizedOutputActive: true, now: start))
    }

    @Test func keyboardAndCorePasteOpenTheWindowButRemoteOutputDoesNot() {
        for paste in [false, true] {
            let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 640, height: 320))
            view.configureForTmuxMirror()
            view.feed(text: "remote output")
            #expect(!view.renderOwner.shouldDisplayImmediatelyAfterUserInput(synchronizedOutputActive: false))
            if paste { view.pasteText("paste") }
            else { view.send(data: Array("key".utf8)[...]) }
            #expect(view.renderOwner.shouldDisplayImmediatelyAfterUserInput(synchronizedOutputActive: false))
        }
    }

    @Test func actualViewFeedRequestsAnEchoTickWithoutADisplayLink() async {
        for paste in [false, true] {
            for byteFeed in [false, true] {
                let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 640, height: 320))
                view.configureForTmuxMirror()
                await drain()
                // No window means no display-link tick can satisfy this test.
                // Report visible to the owner to isolate the feed-to-signal
                // wiring; hidden scheduling is covered separately below.
                view.renderOwner.setTerminalVisibility(.potentiallyVisible)
                view.resetDiagnostics()
                view.feed(text: "ordinary output\u{1b}[c")
                await drain()
                #expect(view.diagnostics.immediateTicks == 0)
                if paste { view.pasteText("paste") }
                else { view.send(data: Array("key".utf8)[...]) }
                await drain()
                view.resetDiagnostics()
                if byteFeed { view.feed(byteArray: Array("echo".utf8)[...]) }
                else { view.feed(text: "echo") }
                await drain()
                #expect(view.diagnostics.immediateTicks > 0)
                #expect(view.diagnostics.frames > 0)
            }
        }
    }

    @Test func echoTicksWithoutVsyncAndBackgroundBurstsCoalesce() async {
        let owner = TerminalRenderOwner()
        let source = ManualTickSource()
        let driver = FrameDriver(tickSource: source)
        defer { driver.shutdown() }
        var frames = 0
        driver.onTick = { frames += 1 }
        driver.markDirty()
        await drain()
        frames = 0
        driver.resetCounters()
        let now: UInt64 = 1_000_000_000
        owner.recordUserInputForDisplay(at: now)
        let signal = driver.signal
        await Task.detached {
            for _ in 0..<1_000 {
                owner.scheduleFrameAfterFeed(false, signal: signal, now: now)
            }
        }.value
        await drain()
        // A background burst can race its main drain, but must produce an
        // immediate frame without a manual display-link tick.
        #expect(frames > 0)
        #expect(frames < 1_000)
        #expect(driver.currentCounters.immediateTicks > 0)
        frames = 0
        driver.resetCounters()
        owner.scheduleFrameAfterFeed(true, signal: signal, now: now)
        await drain()
        #expect(frames == 0)
        #expect(driver.currentCounters.immediateTicks == 0)
        source.tick()
        #expect(frames == 1)
        // Unfreezing inside the input window may request the echo frame.
        frames = 0
        owner.scheduleFrameAfterFeed(false, signal: signal, now: now)
        await drain()
        #expect(frames == 1)
        // Hidden terminals do not wake for an immediate echo frame.
        frames = 0
        driver.resetCounters()
        owner.setTerminalVisibility(.notVisible)
        owner.scheduleFrameAfterFeed(false, signal: signal, now: now)
        await drain()
        #expect(frames == 0)
        #expect(driver.currentCounters.immediateTicks == 0)
        owner.setTerminalVisibility(.potentiallyVisible)
        source.tick()
        // Expired windows and absent sessions stay display-link paced.
        frames = 0
        driver.resetCounters()
        owner.scheduleFrameAfterFeed(false, signal: signal, now: now + 150_000_001)
        owner.scheduleFrameAfterFeed(nil, signal: signal, now: now)
        await drain()
        #expect(frames == 0)
        #expect(driver.currentCounters.immediateTicks == 0)
    }
}
#endif
