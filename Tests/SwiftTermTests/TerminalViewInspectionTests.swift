//
//  TerminalViewInspectionTests.swift
//  SwiftTermTests
//

import Foundation
import Testing
@testable import SwiftTerm

#if os(macOS)
import AppKit

@MainActor
final class TerminalViewInspectionTests {
    @Test func testInspectGeometryMatchesFitEquation() {
        let view = makeView(cols: 80, rows: 24)
        let geo = view.inspectGeometry()

        #expect(geo.cellWidthPoints > 0)
        #expect(geo.cellHeightPoints > 0)
        #expect(geo.engineCols == 80)
        #expect(geo.engineRows == 24)
        #expect(geo.autoResizeGrid == false)
        #expect(geo.boundsWidthPoints == Double(view.bounds.width))
        #expect(geo.boundsHeightPoints == Double(view.bounds.height))
        #expect(geo.effectiveGridWidthPoints == Double(view.getEffectiveWidth(size: view.bounds.size)))
        #expect(
            abs(geo.scrollerReservedWidthPoints - (geo.boundsWidthPoints - geo.effectiveGridWidthPoints)) < 0.001
        )

        // processSizeChange uses floor(effective / cellWidth) when auto-resize is on.
        let expectedCols = Int(geo.effectiveGridWidthPoints / geo.cellWidthPoints)
        let expectedRows = Int(geo.boundsHeightPoints / geo.cellHeightPoints)
        #expect(expectedCols > 0)
        #expect(expectedRows > 0)
        // With a fixed resize(cols:rows:) the engine grid may differ from bounds-derived
        // fit until auto-resize runs; equation itself must still be consistent.
        #expect(geo.effectiveGridWidthPoints + geo.scrollerReservedWidthPoints == geo.boundsWidthPoints
                || abs(geo.effectiveGridWidthPoints + geo.scrollerReservedWidthPoints - geo.boundsWidthPoints) < 0.001)
    }

    @Test func testInspectGeometryReflectsAutoResizeGrid() {
        let view = makeView(cols: 80, rows: 24)
        #expect(view.inspectGeometry().autoResizeGrid == false)
        view.autoResizeGrid = true
        #expect(view.inspectGeometry().autoResizeGrid == true)
        view.autoResizeGrid = false
        #expect(view.inspectGeometry().autoResizeGrid == false)
    }

    @Test func testInspectInputPolicyAllowMouseReporting() {
        let view = makeView(cols: 40, rows: 12)
        #expect(view.inspectInputPolicy().allowMouseReporting == true)
        view.allowMouseReporting = false
        #expect(view.inspectInputPolicy().allowMouseReporting == false)
    }

    @Test func testInspectAllCombinesEngineAndView() {
        let view = makeView(cols: 40, rows: 12)
        view.terminal.feed(text: "hi")
        let all = view.inspectAll()

        #expect(all.terminal.cols == 40)
        #expect(all.terminal.rows == 12)
        #expect(all.terminal.viewportText[0] == "hi")
        #expect(all.geometry.engineCols == 40)
        #expect(all.geometry.engineRows == 12)
        #expect(all.inputPolicy.allowMouseReporting == true)
    }

    @Test func testGeometryCodableSnakeCase() throws {
        let view = makeView(cols: 20, rows: 10)
        let geo = view.inspectGeometry()
        let data = try JSONEncoder().encode(geo)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj?["cell_width_points"] != nil)
        #expect(obj?["effective_grid_width_points"] != nil)
        #expect(obj?["scroller_reserved_width_points"] != nil)
        #expect(obj?["auto_resize_grid"] != nil)
        let decoded = try JSONDecoder().decode(TerminalViewGeometrySnapshot.self, from: data)
        #expect(decoded == geo)
    }

    @Test func testInspectAllCodable() throws {
        let view = makeView(cols: 20, rows: 8)
        view.terminal.feed(text: "x")
        let all = view.inspectAll()
        let data = try JSONEncoder().encode(all)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj?["terminal"] != nil)
        #expect(obj?["geometry"] != nil)
        #expect(obj?["input_policy"] != nil)
        let decoded = try JSONDecoder().decode(TerminalViewInspectionSnapshot.self, from: data)
        #expect(decoded == all)
        let termObj = obj?["terminal"] as? [String: Any]
        #expect(termObj?["content_hash"] is String)
    }

    private func makeView(cols: Int, rows: Int) -> TerminalView {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        // Pin grid so frame adjustments for geometry inspection do not reflow cols/rows.
        view.autoResizeGrid = false
        view.resize(cols: cols, rows: rows)
        view.setFrameSize(NSSize(
            width: view.cellDimension.width * CGFloat(cols) + 20,
            height: view.cellDimension.height * CGFloat(rows)
        ))
        return view
    }
}
#endif
