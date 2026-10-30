#if !SWIFTTERM_EMBEDDED
#if os(macOS) || os(iOS) || os(visionOS) || os(macCatalyst)
import Foundation

/// View preference, separate from the application's DECSCUSR setting.
struct CursorRenderingPolicy: Sendable {
    var blinkEnabled = true
    var styleOverride: CursorStyle?

    func resolve(_ applicationStyle: CursorStyle) -> CursorStyle {
        let style = styleOverride ?? applicationStyle
        guard !blinkEnabled else { return style }
        switch style {
        case .blinkBlock: return .steadyBlock
        case .blinkUnderline: return .steadyUnderline
        case .blinkBar: return .steadyBar
        default: return style
        }
    }
}

extension TerminalView {
    /// Disabling blink preserves the application's requested cursor shape
    /// and its original style, so enabling blink restores that preference.
    public var cursorBlinkEnabled: Bool {
        get { renderOwner.cursorRenderingPolicy.withLock { $0.blinkEnabled } }
        set {
            renderOwner.cursorRenderingPolicy.withLock { $0.blinkEnabled = newValue }
            applyCursorRenderingPolicy()
        }
    }

    /// An optional view-only style override, also applied by the Metal
    /// snapshot renderer. It never changes the terminal's application style.
    public var cursorStyleOverride: CursorStyle? {
        get { renderOwner.cursorRenderingPolicy.withLock { $0.styleOverride } }
        set {
            renderOwner.cursorRenderingPolicy.withLock { $0.styleOverride = newValue }
            applyCursorRenderingPolicy()
        }
    }

    func applyCursorRenderingPolicy(applicationStyle: CursorStyle? = nil) {
        let policy = renderOwner.cursorRenderingPolicy.withLock { $0 }
        let requested = applicationStyle ?? withTerminal { $0.options.cursorStyle }
        let style = policy.resolve(requested)
        caretView?.style = style
        updateCaretView()
        frameDriver.markDirty()
    }
}
#endif
#endif
