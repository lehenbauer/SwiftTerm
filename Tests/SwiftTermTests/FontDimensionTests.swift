#if os(macOS)
import AppKit
import Testing
@testable import SwiftTerm

final class FontDimensionTests {
    @Test func cellWidthSnapsToNearestDevicePixel() throws {
        let font = try #require(NSFont(name: "Monaco", size: 12))
        let view = TerminalView(frame: .zero, font: font)
        let glyph = font.glyph(withName: "W")
        let advance = font.advancement(forGlyph: glyph).width
        let scale = view.backingScaleFactor()
        let expectedWidth = (advance * scale).rounded() / scale

        #expect(view.cellDimension.width == expectedWidth)
        #expect((view.cellDimension.width * scale).rounded() == view.cellDimension.width * scale)
    }

    @Test func publicCellMetricsMatchInstanceComputation() throws {
        let fontNames = ["Menlo", "Monaco", "Courier New"]
        let fontSizes: [CGFloat] = [11, 12, 13, 14]
        let backingScales: [CGFloat] = [1, 2]

        for fontName in fontNames {
            for fontSize in fontSizes {
                let font = try #require(NSFont(name: fontName, size: fontSize))
                let view = TerminalView(frame: .zero, font: font)

                for backingScale in backingScales {
                    let publicMetrics = TerminalView.cellMetrics(font: font,
                                                                 backingScale: backingScale)
                    let instanceMetrics = view.computeFontDimensions(backingScale: backingScale)

                    #expect(publicMetrics == instanceMetrics,
                            "\(fontName) \(fontSize)pt at \(backingScale)x")
                }
            }
        }
    }
}
#endif
