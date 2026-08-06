import XCTest
@testable import LFGCore

final class BrowserPreviewLayoutTests: XCTestCase {
    private let layout = BrowserPreviewLayout(
        containerWidth: 390,
        containerHeight: 700,
        previewWidth: 190,
        previewHeight: 144
    )

    func testConstrainedPointStaysInsideMargins() {
        XCTAssertEqual(
            layout.constrained(BrowserPreviewPoint(x: -100, y: -100)),
            BrowserPreviewPoint(x: 105, y: 82)
        )
        XCTAssertEqual(
            layout.constrained(BrowserPreviewPoint(x: 900, y: 900)),
            BrowserPreviewPoint(x: 285, y: 618)
        )
    }

    func testRestingAtAnEdgeDoesNotDockWithoutOvershoot() {
        XCTAssertNil(layout.dockEdge(forUnconstrainedX: layout.leadingCenterX))
        XCTAssertNil(layout.dockEdge(forUnconstrainedX: layout.trailingCenterX))
    }

    func testDraggingPastEitherEdgeDocks() {
        XCTAssertEqual(
            layout.dockEdge(forUnconstrainedX: layout.leadingCenterX - 25),
            .leading
        )
        XCTAssertEqual(
            layout.dockEdge(forUnconstrainedX: layout.trailingCenterX + 25),
            .trailing
        )
    }

    func testNarrowContainerUsesOneStableHorizontalCenter() {
        let narrow = BrowserPreviewLayout(
            containerWidth: 180,
            containerHeight: 300,
            previewWidth: 190,
            previewHeight: 144
        )
        XCTAssertEqual(narrow.leadingCenterX, 90)
        XCTAssertEqual(narrow.trailingCenterX, 90)
        XCTAssertEqual(
            narrow.constrained(BrowserPreviewPoint(x: 400, y: 150)).x,
            90
        )
    }
}
