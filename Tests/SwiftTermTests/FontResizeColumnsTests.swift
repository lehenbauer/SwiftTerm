//
//  FontResizeColumnsTests.swift
//  SwiftTerm
//
//  Regression tests for terminal columns and macOS scroller styles.
//

#if os(macOS)
import Foundation
import Testing
import AppKit
@testable import SwiftTerm

@MainActor
@Suite(.serialized)
struct FontResizeColumnsTests {
    @Test func testOverlayScrollerDoesNotRemoveColumns() {
        let frame = CGRect(x: 0, y: 0, width: 400, height: 200)
        let view = TerminalView(frame: frame)
        view.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        let renderedWidth = CGFloat(view.withTerminal { $0.cols }) * view.cellDimension.width
        let usableWidth = view.getEffectiveWidth(size: frame.size)

        #expect(view.scrollerStyle == .overlay)
        #expect(usableWidth == frame.width)
        #expect(renderedWidth <= usableWidth)
        #expect(usableWidth - renderedWidth < view.cellDimension.width)
    }

    @Test func testLegacyScrollerReservesItsWidth() {
        let frame = CGRect(x: 0, y: 0, width: 400, height: 200)
        let view = TerminalView(frame: frame)
        view.scrollerStyle = .legacy
        view.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        let renderedWidth = CGFloat(view.withTerminal { $0.cols }) * view.cellDimension.width
        let usableWidth = view.getEffectiveWidth(size: frame.size)

        #expect(usableWidth < frame.width)
        #expect(renderedWidth <= usableWidth)
        #expect(usableWidth - renderedWidth < view.cellDimension.width)
    }

    @Test func testOverlayScrollerAppearsOnDemand() async throws {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        let scroller = view.subviews.compactMap { $0 as? NSScroller }.first
        let indicator = view.subviews.first {
            $0.identifier?.rawValue == "SwiftTermOverlayScrollerIndicator"
        }

        #expect(scroller?.alphaValue == 0)
        #expect(scroller?.isHidden == true)
        #expect(scroller?.controlSize == .small)
        #expect(indicator?.isHidden == true)
        #expect(indicator?.isFlipped == true)
        view.applyScrollerState(.init(isEnabled: true, doubleValue: 0.5, knobProportion: 0.2))
        view.showOverlayScroller()
        #expect(scroller?.alphaValue == 0)
        #expect(scroller?.isHidden == false)
        #expect(indicator?.isHidden == false)
        #expect(indicator?.alphaValue == 1)
        view.layoutSubtreeIfNeeded()
        if let scroller {
            let point = CGPoint(x: scroller.frame.midX, y: scroller.frame.midY)
            #expect(view.hitTest(point) === scroller)
        }
        try await Task.sleep(for: .seconds(2))
        #expect(scroller?.isHidden == true)
        #expect(indicator?.isHidden == true)
    }

    /// AppKit keeps the drawing `NSScroller` subclass on the legacy style, so
    /// the transparent overlay hit target must not paint legacy chrome under
    /// the indicator whenever it is invalidated.
    @Test func testOverlayHitTargetPaintsNothing() throws {
        func paintedPixels(_ style: NSScroller.Style) throws -> Int {
            let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
            view.followsSystemScrollerStyle = false
            view.scrollerStyle = style
            view.layoutSubtreeIfNeeded()
            let scroller = try #require(view.subviews.compactMap { $0 as? NSScroller }.first)
            view.applyScrollerState(.init(isEnabled: true, doubleValue: 0.5, knobProportion: 0.2))
            let rep = try #require(scroller.bitmapImageRepForCachingDisplay(in: scroller.bounds))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            scroller.draw(scroller.bounds)
            NSGraphicsContext.restoreGraphicsState()
            var painted = 0
            for x in 0..<rep.pixelsWide {
                for y in 0..<rep.pixelsHigh where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0 {
                    painted += 1
                }
            }
            return painted
        }

        #expect(try paintedPixels(.legacy) > 0)
        #expect(try paintedPixels(.overlay) == 0)
    }

    @Test func testScrollerUsesTerminalScrollPositionDirectly() {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        let scroller = view.subviews.compactMap { $0 as? NSScroller }.first

        view.applyScrollerState(.init(isEnabled: true, doubleValue: 1, knobProportion: 0.2))
        #expect(scroller?.doubleValue == 1)
    }

    /// The font-change path (`resetFont`) and the live-resize path
    /// (`processSizeChange`) must agree on the column count for a given frame,
    /// so zooming the font in and back out never drifts the column count.
    @Test func testFontChangeColumnsMatchResizePath() {
        let frame = CGRect(x: 0, y: 0, width: 400, height: 200)
        let view = TerminalView(frame: frame)
        view.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        let colsAfterFontChange = view.withTerminal { $0.cols }
        view.processSizeChange(newSize: frame.size)
        let colsAfterResize = view.withTerminal { $0.cols }

        #expect(colsAfterFontChange == colsAfterResize)
    }
}
#endif
