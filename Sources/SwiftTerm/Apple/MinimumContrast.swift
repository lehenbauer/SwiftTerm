//
//  MinimumContrast.swift
//  SwiftTerm
//
//  Perceptual minimum-contrast adjustment for a (foreground, background) color pair.
//
//  When a foreground color is too close in lightness to its background, the
//  foreground is nudged darker or brighter (in CIE L*) until a caller-specified
//  minimum lightness difference is satisfied. The chrominance is preserved as
//  much as possible by scaling the linear RGB components uniformly to hit the
//  target luminance.
//
//  This is used by the terminal view's per-cell rendering path to keep arbitrary
//  ANSI output legible against light or dark backgrounds without requiring the
//  host application to curate a perfect palette.
//

#if os(macOS) || os(iOS) || os(visionOS)
import Foundation
import CoreGraphics

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Extracts sRGB components and alpha from a platform color. On macOS the color
/// is first converted into the sRGB colorspace so non-RGB colors (named, system,
/// catalog) still produce sane values.
private func srgbComponents(_ color: TTColor) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)? {
    #if os(macOS)
    guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
    rgb.getRed(&r, green: &g, blue: &b, alpha: &a)
    return (r, g, b, a)
    #else
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
    guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
    return (r, g, b, a)
    #endif
}

/// sRGB inverse companding (gamma decode) for one channel: 0…1 sRGB -> 0…1 linear.
private func srgbToLinear(_ c: CGFloat) -> CGFloat {
    return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
}

/// sRGB forward companding (gamma encode) for one channel: 0…1 linear -> 0…1 sRGB.
private func linearToSrgb(_ c: CGFloat) -> CGFloat {
    let clamped = min(max(c, 0), 1)
    return clamped <= 0.0031308 ? 12.92 * clamped : 1.055 * pow(clamped, 1.0 / 2.4) - 0.055
}

/// Relative luminance Y from linear sRGB (Rec. 709 / sRGB matrix row).
private func relativeLuminance(rL: CGFloat, gL: CGFloat, bL: CGFloat) -> CGFloat {
    return 0.2126 * rL + 0.7152 * gL + 0.0722 * bL
}

/// CIE L* from relative luminance Y (D65 reference white). Output range 0…100.
private func lStarFromLuminance(_ y: CGFloat) -> CGFloat {
    return y > 0.008856 ? 116.0 * pow(y, 1.0 / 3.0) - 16.0 : 903.3 * y
}

/// Inverse of `lStarFromLuminance`: linear luminance Y from CIE L*.
private func luminanceFromLStar(_ l: CGFloat) -> CGFloat {
    if l > 8.0 {
        let t = (l + 16.0) / 116.0
        return t * t * t
    } else {
        return l / 903.3
    }
}

/// Construct a TTColor from sRGB-companded components, preserving the supplied alpha.
private func makeColor(r: CGFloat, g: CGFloat, b: CGFloat, alpha: CGFloat) -> TTColor {
    let clamp: (CGFloat) -> CGFloat = { min(max($0, 0), 1) }
    #if os(macOS)
    return NSColor(srgbRed: clamp(r), green: clamp(g), blue: clamp(b), alpha: alpha)
    #else
    return UIColor(red: clamp(r), green: clamp(g), blue: clamp(b), alpha: alpha)
    #endif
}

/// Adjust `fg` so that its perceptual lightness (CIE L*) differs from `bg`'s by
/// at least `minimum` (expressed in 0…1, scaled internally to the 0…100 L* range).
///
/// Returns `fg` unchanged when:
///   * `minimum <= 0`,
///   * either color's components can't be extracted,
///   * or the existing lightness difference already meets the threshold.
///
/// When adjustment is required, `fg`'s lightness is moved away from `bg`'s until
/// the threshold is met; the original chrominance is preserved by scaling the
/// linear RGB components uniformly. Alpha is preserved from `fg`.
internal func adjustedForegroundForMinimumContrast(_ fg: TTColor,
                                                   against bg: TTColor,
                                                   minimum: CGFloat) -> TTColor {
    if minimum <= 0 { return fg }
    guard let fgC = srgbComponents(fg), let bgC = srgbComponents(bg) else { return fg }

    let fgRL = srgbToLinear(fgC.r)
    let fgGL = srgbToLinear(fgC.g)
    let fgBL = srgbToLinear(fgC.b)
    let bgRL = srgbToLinear(bgC.r)
    let bgGL = srgbToLinear(bgC.g)
    let bgBL = srgbToLinear(bgC.b)

    let fgY = relativeLuminance(rL: fgRL, gL: fgGL, bL: fgBL)
    let bgY = relativeLuminance(rL: bgRL, gL: bgGL, bL: bgBL)
    let fgL = lStarFromLuminance(fgY)
    let bgL = lStarFromLuminance(bgY)

    let threshold = min(max(minimum, 0), 1) * 100.0
    if abs(fgL - bgL) >= threshold { return fg }

    // Primary nudge: push fg in the direction it already lies relative to bg.
    let preferDarker = fgL <= bgL
    var targetL = preferDarker ? max(0, bgL - threshold) : min(100, bgL + threshold)

    // If clamping prevented us from reaching the threshold, try the other direction
    // and keep whichever produces the larger actual lightness gap.
    if abs(targetL - bgL) < threshold - 0.001 {
        let alt: CGFloat = preferDarker ? min(100, bgL + threshold) : max(0, bgL - threshold)
        if abs(alt - bgL) > abs(targetL - bgL) {
            targetL = alt
        }
    }

    let targetY = luminanceFromLStar(targetL)

    // Preserve chrominance by scaling the linear RGB components uniformly. When
    // the source is essentially black (Y ~ 0) there's no chrominance to keep, so
    // emit a neutral grey of the target luminance.
    let newR: CGFloat
    let newG: CGFloat
    let newB: CGFloat
    if fgY > 1e-6 {
        let scale = targetY / fgY
        newR = linearToSrgb(fgRL * scale)
        newG = linearToSrgb(fgGL * scale)
        newB = linearToSrgb(fgBL * scale)
    } else {
        let neutral = linearToSrgb(targetY)
        newR = neutral
        newG = neutral
        newB = neutral
    }

    return makeColor(r: newR, g: newG, b: newB, alpha: fgC.a)
}

#endif
