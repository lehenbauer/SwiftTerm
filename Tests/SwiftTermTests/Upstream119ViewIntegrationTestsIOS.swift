//
//  Upstream119ViewIntegrationTestsIOS.swift
//
//  iOS half of Upstream119ViewIntegrationTests: the iOS view keeps its
//  default background (and its `backgroundOpacity` alpha) on the layer, and
//  DECSCNM stashes that layer color in `reverseColorsSavedLayerBackground`.
//  The appearance API must compose with both. Runs only under an iOS
//  destination (xcodebuild); `swift test` on macOS compiles it out.
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

    @Test func appearanceSwitchPreservesLayerOpacity() {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        view.backgroundOpacity = 0.4
        // Control: the opacity API itself works.
        #expect(RGBA(view.layer.backgroundColor).a == 40)

        view.terminalAppearance = .light
        let layer = RGBA(view.layer.backgroundColor)
        #expect(layer.rgb == RGBA(view.lightTheme.background).rgb)
        #expect(layer.a == 40, "layer after light switch: \(layer)")
        #expect(abs(view.backgroundOpacity - 0.4) < 0.01)
    }

    @Test func reverseScreenAcrossThemeSwitchRestoresNewThemeBackground() {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        view.terminalAppearance = .dark
        view.backgroundOpacity = 0.4
        let dark = view.darkTheme

        view.terminal.feed(text: "\(esc)[?5h")
        #expect(RGBA(view.layer.backgroundColor).rgb == RGBA(dark.foreground).rgb)
        #expect(RGBA(view.layer.backgroundColor).a == 40, "control: reverse keeps opacity")
        view.terminal.feed(text: "\(esc)[?5l")
        #expect(RGBA(view.layer.backgroundColor).rgb == RGBA(dark.background).rgb, "control: reverse off restores")

        view.terminal.feed(text: "\(esc)[?5h")
        view.terminalAppearance = .light
        let light = view.lightTheme
        #expect(RGBA(view.layer.backgroundColor).rgb == RGBA(light.foreground).rgb,
                "reversed layer after theme switch: \(RGBA(view.layer.backgroundColor))")

        view.terminal.feed(text: "\(esc)[?5l")
        let restored = RGBA(view.layer.backgroundColor)
        #expect(restored.rgb == RGBA(light.background).rgb,
                "reverse off restored a stale pre-switch background: \(restored)")
        #expect(restored.a == 40, "reverse off after theme switch: \(restored)")
    }
}
#endif
