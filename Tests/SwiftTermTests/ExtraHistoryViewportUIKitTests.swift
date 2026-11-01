#if os(iOS)
import UIKit
import XCTest
@testable import SwiftTerm

@MainActor
final class ExtraHistoryViewportUIKitTests: XCTestCase {
    func testExpandedHistoryMatchesTallerTerminalWithoutChangingAddressing() async throws {
        let font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let cell = TerminalView.cellMetrics(font: font, backingScale: UIScreen.main.scale)
        let frame = CGRect(x: 0, y: 0, width: ceil(cell.width * 40), height: cell.height * 40)
        let window = UIWindow(frame: UIScreen.main.bounds)
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        func makeView(rows: Int) -> TerminalView {
            TerminalView(frame: frame, font: font, terminalOptions: .default,
                         initialGeometry: .grid(cols: 40, rows: rows), autoResizeGrid: false)
        }
        let small = makeView(rows: 20)
        let reference = makeView(rows: 40)
        let text = "\u{1b}[?25l" + (1...100).map { String(format: "ROW %03d\r\n", $0) }.joined()
        small.feed(text: text)
        reference.feed(text: text)
        func pixels(_ view: TerminalView) async -> Data? {
            root.view.subviews.forEach { $0.removeFromSuperview() }
            let viewport = UIView(frame: frame)
            root.view.addSubview(viewport)
            viewport.addSubview(view)
            view.frame = frame
            view.layoutIfNeeded()
            view.scrollToBottom()
            view.requestFullDisplayRefresh()
            try? await Task.sleep(for: .milliseconds(150))
            // Package tests have no foreground app scene, so drawHierarchy
            // returns black even with a valid native render snapshot. Exercise
            // the actual Core Graphics draw entry with its scroll transform.
            let data = UIGraphicsImageRenderer(size: frame.size).image { context in
                context.cgContext.translateBy(x: 0, y: -view.contentOffset.y)
                view.draw(view.bounds)
            }.pngData()
            if let data {
                let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            return data
        }
        let expected = await pixels(reference)
        let unexpanded = await pixels(small)
        XCTAssertNotNil(expected)
        XCTAssertNotEqual(unexpanded, expected, "old rendering omits the extra history rows")
        small.fillsExtraViewportFromHistory = true
        let expanded = await pixels(small)
        XCTAssertEqual(expanded, expected, "extra history plus the live grid must match the taller reference")
        XCTAssertEqual(small.terminalDimensions, TerminalDimensions(cols: 40, rows: 20))

        // CUP row 1 still addresses the first LIVE row, below 20 history rows.
        small.feed(text: "\u{1b}[1;1H\u{1b}[2KCHANGED LIVE ROW")
        reference.feed(text: "\u{1b}[21;1H\u{1b}[2KCHANGED LIVE ROW")
        let changed = await pixels(small)
        let changedReference = await pixels(reference)
        XCTAssertEqual(changed, changedReference)

        small.feed(text: "\u{1b}[?1049h\u{1b}[2J\u{1b}[HALTERNATE")
        _ = await pixels(small)
        small.renderOwner.withSnapshotForDrawing(viewState: FrameViewState(view: small)) { snapshot, _ in
            XCTAssertEqual(snapshot.rowCount, 20)
            XCTAssertEqual(snapshot.firstRow, 0)
        }
        small.feed(text: "\u{1b}[?1049l")
        _ = await pixels(small)
        small.renderOwner.withSnapshotForDrawing(viewState: FrameViewState(view: small)) { snapshot, _ in
            XCTAssertEqual(snapshot.rowCount, 40)
            XCTAssertEqual(snapshot.rows.count, 40)
        }
    }
}
#endif
