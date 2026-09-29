//
//  Upstream119ViewIntegrationTestsIOS.swift
//
//  iOS half of Upstream119ViewIntegrationTests: the iOS view keeps its
//  default background (and its `backgroundOpacity` alpha) on the layer, and
//  DECSCNM stashes that layer color in `reverseColorsSavedLayerBackground`.
//  Applying a theme adopts its background alpha, and must compose with both.
//  Runs only under an iOS destination (xcodebuild); `swift test` on macOS
//  compiles it out.
//
#if os(iOS)
import Testing
import UIKit

@testable import SwiftTerm

private struct RGBA: Equatable, CustomStringConvertible {
    let r: Int, g: Int, b: Int, a: Int

    init(_ color: CGColor?) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        if let color {
            UIColor(cgColor: color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        }
        r = Int((red * 255).rounded())
        g = Int((green * 255).rounded())
        b = Int((blue * 255).rounded())
        a = Int((alpha * 100).rounded())
    }

    init(_ color: UIColor) { self.init(color.cgColor) }

    var rgb: [Int] { [r, g, b] }
    var description: String { "rgb(\(r),\(g),\(b)) a=\(a)%" }
}

@MainActor
@Suite(.serialized)
final class Upstream119ViewIntegrationTestsIOS {
    private let esc = "\u{1b}"

    // Contract (coordinator decision): applying a theme adopts its
    // background alpha; it does not preserve a previously set
    // `backgroundOpacity`. On iOS the default background lives on the layer.

    private func theme(fg: (Int, Int, Int), bg: (Int, Int, Int), alpha: CGFloat) -> TerminalTheme {
        func c(_ v: (Int, Int, Int), _ a: CGFloat = 1) -> UIColor {
            UIColor(red: CGFloat(v.0) / 255, green: CGFloat(v.1) / 255, blue: CGFloat(v.2) / 255, alpha: a)
        }
        var t = TerminalTheme.swiftTermDark
        t.foreground = c(fg)
        t.background = c(bg, alpha)
        t.caret = c(fg)
        t.caretText = c(bg)
        return t
    }

    private var translucentDark: TerminalTheme { theme(fg: (220, 210, 190), bg: (20, 30, 50), alpha: 0.2) }
    private var translucentLight: TerminalTheme { theme(fg: (40, 20, 10), bg: (240, 230, 210), alpha: 0.4) }
    private var opaqueLight: TerminalTheme { theme(fg: (10, 60, 10), bg: (250, 250, 235), alpha: 1) }

    private func install(_ view: TerminalView, dark: TerminalTheme, light: TerminalTheme) {
        view.lightTheme = light      // not applied: resolved appearance is dark
        view.darkTheme = dark        // applied
        view.terminalAppearance = .dark
    }

    @Test func translucentThemesApplyThemeAlphaAcrossSwitches() {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        let dark = translucentDark, light = translucentLight
        install(view, dark: dark, light: light)
        for (name, t) in [("dark", dark), ("light", light), ("dark again", dark)] {
            view.terminalAppearance = name.hasPrefix("dark") ? .dark : .light
            let layer = RGBA(view.layer.backgroundColor)
            #expect(layer == RGBA(t.background), "\(name): layer \(layer)")
            #expect(abs(view.backgroundOpacity - t.background.cgColor.alpha) < 0.01, "\(name): opacity \(view.backgroundOpacity)")
        }
    }

    /// Control protecting the existing theme-alpha API.
    @Test func opaqueThemeAfterTranslucentOpacityRestoresOpacityOne() {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        view.backgroundOpacity = 0.4
        #expect(RGBA(view.layer.backgroundColor).a == 40, "control: opacity API")
        view.lightTheme = opaqueLight
        view.terminalAppearance = .light
        #expect(RGBA(view.layer.backgroundColor) == RGBA(opaqueLight.background))
        #expect(abs(view.backgroundOpacity - 1) < 0.01)
    }

    /// DECSCNM across a switch between differing translucent themes: while
    /// still reversed, the swapped foreground must already be the new theme's
    /// background; reverse-off must land on the new theme's background + alpha.
    @Test func reverseScreenAcrossThemeSwitchRestoresNewThemeBackground() {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        let dark = translucentDark, light = translucentLight
        install(view, dark: dark, light: light)

        view.terminal.feed(text: "\(esc)[?5h")
        #expect(RGBA(view.layer.backgroundColor) == RGBA(dark.foreground.withAlphaComponent(dark.background.cgColor.alpha)),
                "control: reversed layer \(RGBA(view.layer.backgroundColor))")
        #expect(RGBA(view.effectiveNativeForegroundColor).rgb == RGBA(dark.background).rgb, "control: reversed fg")
        view.terminal.feed(text: "\(esc)[?5l")
        #expect(RGBA(view.layer.backgroundColor) == RGBA(dark.background), "control: reverse off restores")

        view.terminal.feed(text: "\(esc)[?5h")
        view.terminalAppearance = .light
        #expect(RGBA(view.layer.backgroundColor) == RGBA(light.foreground.withAlphaComponent(light.background.cgColor.alpha)),
                "reversed layer after theme switch: \(RGBA(view.layer.backgroundColor))")
        let reversedFg = RGBA(view.effectiveNativeForegroundColor)
        #expect(reversedFg.rgb == RGBA(light.background).rgb,
                "reversed fg after theme switch (before reverse off) is stale: \(reversedFg)")

        view.terminal.feed(text: "\(esc)[?5l")
        let restored = RGBA(view.layer.backgroundColor)
        #expect(restored == RGBA(light.background),
                "reverse off restored a stale pre-switch background: \(restored)")
    }
}
#endif
