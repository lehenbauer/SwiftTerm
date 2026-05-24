//
//  MinimumContrastTests.swift
//

#if os(macOS)
import Foundation
import Testing
import AppKit

@testable import SwiftTerm

/// Returns the CIE L* value of `color` using the same sRGB-companding +
/// relative-luminance pipeline that `adjustedForegroundForMinimumContrast`
/// uses internally. Kept tiny and inline so we don't need to expose any of
/// the private helpers in `MinimumContrast.swift`.
private func lStar(_ color: NSColor) -> CGFloat {
    let srgb = color.usingColorSpace(.sRGB)!
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
    srgb.getRed(&r, green: &g, blue: &b, alpha: &a)
    let lin: (CGFloat) -> CGFloat = { c in c <= 0.04045 ? c/12.92 : pow((c + 0.055)/1.055, 2.4) }
    let y = 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    return y > 0.008856 ? 116.0 * pow(y, 1.0/3.0) - 16.0 : 903.3 * y
}

final class MinimumContrastTests {
    @Test func zeroThresholdNoOp() {
        let fg = NSColor.white
        let bg = NSColor.white
        let out = adjustedForegroundForMinimumContrast(fg, against: bg, minimum: 0)
        #expect(out === fg)
    }

    @Test("Returns input unchanged when threshold already met")
    func alreadyMeetsThreshold() {
        let fg = NSColor.black
        let bg = NSColor.white
        let out = adjustedForegroundForMinimumContrast(fg, against: bg, minimum: 0.5)
        #expect(out === fg)
    }

    @Test("Pushes fg darker when fg ≈ bg on light background")
    func nudgesAwayOnLightBg() {
        let bg = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        let nearWhite = NSColor(srgbRed: 0.95, green: 0.95, blue: 0.95, alpha: 1)
        let out = adjustedForegroundForMinimumContrast(nearWhite, against: bg, minimum: 0.3)
        let delta = abs(lStar(out) - lStar(bg))
        #expect(delta >= 29.0)
    }

    @Test("Pushes fg lighter when fg ≈ bg on dark background")
    func nudgesAwayOnDarkBg() {
        let bg = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        let nearBlack = NSColor(srgbRed: 0.05, green: 0.05, blue: 0.05, alpha: 1)
        let out = adjustedForegroundForMinimumContrast(nearBlack, against: bg, minimum: 0.3)
        let delta = abs(lStar(out) - lStar(bg))
        #expect(delta >= 29.0)
    }

    @Test("Preserves fg alpha")
    func preservesAlpha() {
        let fg = NSColor(srgbRed: 0.95, green: 0.95, blue: 0.95, alpha: 0.42)
        let bg = NSColor.white
        let out = adjustedForegroundForMinimumContrast(fg, against: bg, minimum: 0.3)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        out.usingColorSpace(.sRGB)!.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(abs(a - 0.42) < 0.001)
    }

    @Test("Handles pure-black foreground (Y == 0) without crashing")
    func pureBlackOnBlack() {
        let bg = NSColor.black
        let fg = NSColor.black
        let out = adjustedForegroundForMinimumContrast(fg, against: bg, minimum: 0.5)
        // Must produce *some* readable color (not black) — algorithm flips to
        // a neutral grey of the target luminance in this edge case.
        #expect(lStar(out) >= 40.0)
    }
}
#endif
