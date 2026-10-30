#if !SWIFTTERM_EMBEDDED
#if os(macOS) || os(iOS) || os(visionOS) || os(macCatalyst)
import Foundation

extension TerminalView {
    func synchronizeAutoResizePolicy() {
        guard let terminal else { return }
        terminal.terminalLock.withLock {
            terminal.allowsViewResize = autoResizeGrid
            terminal.viewResizeGeneration &+= 1
        }
        renderOwner.mailbox.discardPendingSize()
    }

    /// Configures a view that displays a tmux terminal's output. Call before
    /// the first feed. Host policy survives terminal resets: emulator replies
    /// are suppressed, output does not clear a copy selection, and OSC 133
    /// cannot move cells or turn clicks into prompt-editing input.
    ///
    /// Real keys, paste and mouse input remain enabled. A host may also opt
    /// into reports for real focus changes; enabling mode 1004 in remote
    /// output still never generates a reply.
    public func configureForTmuxMirror(reportUserFocusChanges: Bool = false) {
        withTerminal { terminal in
            terminal.isTmuxMirror = true
            terminal.mirrorReportsUserFocusChanges = reportUserFocusChanges
            terminal.registerOscHandler(code: 133) { _ in }
        }
        #if os(iOS) || os(visionOS)
        // The host owns one-finger scrolling. Reconcile every entry point,
        // including a view configured after an alternate buffer was activated.
        refreshProgramScrollGesture()
        #endif
    }

    /// Marks the current terminal content dirty as well as scheduling a
    /// frame. Use after rehosting a view or exposing a stale render surface.
    public func requestFullDisplayRefresh() {
        withTerminal { $0.updateFullScreen() }
        frameDriver.markDirty()
    }
}
#endif
#endif
