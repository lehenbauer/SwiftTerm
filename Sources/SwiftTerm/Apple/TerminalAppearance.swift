//
//  TerminalAppearance.swift
//  SwiftTerm
//
//  Light/dark/system appearance support for the terminal view, plus two
//  built-in themes that work well out of the box.
//
//  Hosts opt in per view by setting `terminalView.appearance`. When the value
//  is `.system`, the view observes its platform's appearance signal
//  (`viewDidChangeEffectiveAppearance` on macOS, `traitCollectionDidChange` on
//  iOS) and re-resolves automatically. The default value of `appearance` is
//  `.dark`, which preserves the pre-existing color behavior for any consumer
//  that never touches the new API.
//

#if os(macOS) || os(iOS) || os(visionOS)
import Foundation
import CoreGraphics

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// How a terminal view picks between its light and dark themes.
public enum TerminalAppearance: Sendable, Equatable {
    /// Follow the current OS appearance and update automatically when it changes.
    case system
    /// Use `TerminalView.lightTheme` regardless of OS appearance.
    case light
    /// Use `TerminalView.darkTheme` regardless of OS appearance.
    case dark
}

/// Bundles the colors a `TerminalView` uses for its non-content chrome
/// (foreground, background, caret, selection) plus the 16-color ANSI palette
/// and the strategy for deriving the extended 256-color palette.
///
/// Two built-in presets — `swiftTermLight` and `swiftTermDark` — are designed
/// to look reasonable out of the box without per-app curation. Pair the light
/// preset with a non-zero `TerminalView.minimumContrast` (e.g. `0.3`) so
/// arbitrary ANSI output stays legible against the lighter background.
public struct TerminalTheme {
    public var foreground: TTColor
    public var background: TTColor
    public var boldForeground: TTColor?
    public var caret: TTColor
    public var caretText: TTColor?
    public var selectionBackground: TTColor
    public var ansi16: [Color]
    public var ansi256Strategy: Ansi256PaletteStrategy

    public init(foreground: TTColor,
                background: TTColor,
                boldForeground: TTColor? = nil,
                caret: TTColor,
                caretText: TTColor? = nil,
                selectionBackground: TTColor,
                ansi16: [Color],
                ansi256Strategy: Ansi256PaletteStrategy = .base16Lab) {
        self.foreground = foreground
        self.background = background
        self.boldForeground = boldForeground
        self.caret = caret
        self.caretText = caretText
        self.selectionBackground = selectionBackground
        self.ansi16 = ansi16
        self.ansi256Strategy = ansi256Strategy
    }
}

extension TerminalTheme {
    /// Mirrors the pre-existing SwiftTerm defaults so hosts that opt into the
    /// appearance API with `.dark` see no visual change from prior behavior.
    public static var swiftTermDark: TerminalTheme {
        #if os(macOS)
        let selection = NSColor.selectedTextBackgroundColor
        #else
        let selection = UIColor(red: 204.0/255.0, green: 221.0/255.0, blue: 237.0/255.0, alpha: 1.0)
        #endif
        return TerminalTheme(
            foreground: TTColor.make(color: Color.defaultForeground),
            background: TTColor.make(color: Color.defaultBackground),
            boldForeground: nil,
            caret: TTColor.make(color: Color.defaultForeground),
            caretText: nil,
            selectionBackground: selection,
            ansi16: Color.terminalAppColors,
            ansi256Strategy: .base16Lab)
    }

    /// A light preset that pairs a near-black foreground with a warm white
    /// background and reuses the dark theme's ANSI palette. ANSI legibility on
    /// light backgrounds is preserved by the per-cell minimum-contrast guard;
    /// set `TerminalView.minimumContrast = 0.3` (or so) alongside this theme.
    public static var swiftTermLight: TerminalTheme {
        let nearBlack = Color(red8: 0x1c, green8: 0x1c, blue8: 0x1c)
        let warmWhite = Color(red8: 0xfa, green8: 0xfa, blue8: 0xfa)
        let paleBlue = Color(red8: 0xcf, green8: 0xe2, blue8: 0xf3)
        return TerminalTheme(
            foreground: TTColor.make(color: nearBlack),
            background: TTColor.make(color: warmWhite),
            boldForeground: nil,
            caret: TTColor.make(color: nearBlack),
            caretText: TTColor.make(color: warmWhite),
            selectionBackground: TTColor.make(color: paleBlue),
            ansi16: Color.terminalAppColors,
            ansi256Strategy: .base16Lab)
    }
}

extension TerminalView {

    /// Resolves the abstract `terminalAppearance` value into a concrete
    /// light/dark bit using the platform's appearance signal when `.system`
    /// is in effect.
    func resolvedIsDarkAppearance() -> Bool {
        switch terminalAppearance {
        case .light: return false
        case .dark: return true
        case .system:
            #if os(macOS)
            if let match = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) {
                return match == .darkAqua
            }
            return true
            #else
            return traitCollection.userInterfaceStyle == .dark
            #endif
        }
    }

    /// Picks the theme matching the currently-resolved appearance and applies
    /// every field onto the view. Called by the `appearance` / theme setters
    /// and by the platform appearance observers.
    ///
    /// Intentionally NOT invoked from view initialization — the existing init
    /// color paths stand until the host opts in, so the iOS transparency setup
    /// at `setupOptions()` (background goes onto `layer.backgroundColor`,
    /// `nativeBackgroundColor` is set to `.clear`) is not clobbered before a
    /// host actually wants to override it.
    func applyResolvedAppearance() {
        let theme = resolvedIsDarkAppearance() ? darkTheme : lightTheme

        nativeForegroundColor = theme.foreground
        #if os(macOS)
        nativeBackgroundColor = theme.background
        layer?.backgroundColor = theme.background.cgColor
        #else
        // Mirror the init-time transparency dance: actual bg lives on the
        // layer; cell-level default bg is transparent so it doesn't paint over.
        layer.backgroundColor = theme.background.cgColor
        nativeBackgroundColor = TTColor.clear
        #endif

        nativeBoldForegroundColor = theme.boldForeground
        caretColor = theme.caret
        caretTextColor = theme.caretText
        selectedTextBackgroundColor = theme.selectionBackground

        // Set the strategy onto options directly so installColors performs a
        // single palette rebuild instead of two (the public setter on Terminal
        // would also trigger a rebuild on its own).
        terminal.options.ansi256PaletteStrategy = theme.ansi256Strategy
        installColors(theme.ansi16)
        // installColors invokes colorsChanged(); the other property setters
        // above don't, but the cache flush from installColors covers them.
    }
}

#endif
