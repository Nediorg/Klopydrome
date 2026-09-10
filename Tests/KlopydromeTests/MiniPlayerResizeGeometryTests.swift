import XCTest
@testable import Klopydrome

/// `MiniPlayerResizeGeometry.contentSize` applies to the OPEN detail panel
/// only. The collapsed square is enforced natively by the panel's 1:1
/// `contentAspectRatio` and is intentionally not re-derived here.
final class MiniPlayerResizeGeometryTests: XCTestCase {

    func testVerticalResizeStretchesPanelAndKeepsArtworkWidth() {
        let size = MiniPlayerResizeGeometry.contentSize(
            requested: NSSize(width: 420, height: 900),
            current: NSSize(width: 420, height: 720)
        )

        XCTAssertEqual(size.width, 420, accuracy: 0.001)
        XCTAssertEqual(size.height, 900, accuracy: 0.001)
        XCTAssertEqual(size.height - size.width, 480, accuracy: 0.001)
    }

    func testHorizontalResizeKeepsWindowHeightAndPanelGivesUpSpace() {
        let size = MiniPlayerResizeGeometry.contentSize(
            requested: NSSize(width: 560, height: 800),
            current: NSSize(width: 420, height: 800)
        )

        XCTAssertEqual(size.width, 560, accuracy: 0.001)
        XCTAssertEqual(size.height, 800, accuracy: 0.001)
        XCTAssertEqual(size.height - size.width, 240, accuracy: 0.001)
    }

    func testHorizontalShrinkReturnsSpaceToThePanel() {
        let size = MiniPlayerResizeGeometry.contentSize(
            requested: NSSize(width: 380, height: 800),
            current: NSSize(width: 420, height: 800)
        )

        XCTAssertEqual(size.width, 380, accuracy: 0.001)
        XCTAssertEqual(size.height, 800, accuracy: 0.001)
    }

    func testHorizontalGrowStopsAtPanelMinimum() {
        let size = MiniPlayerResizeGeometry.contentSize(
            requested: NSSize(width: 700, height: 720),
            current: NSSize(width: 420, height: 720)
        )

        XCTAssertEqual(size.width, 700, accuracy: 0.001)
        XCTAssertEqual(
            size.height - size.width,
            MiniPlayerLayout.minimumDetailHeight,
            accuracy: 0.001
        )
    }

    func testDetailPanelKeepsMinimumHeightDuringVerticalResize() {
        let size = MiniPlayerResizeGeometry.contentSize(
            requested: NSSize(width: 420, height: 430),
            current: NSSize(width: 420, height: 720)
        )

        XCTAssertEqual(size.width, 420, accuracy: 0.001)
        XCTAssertEqual(
            size.height - size.width,
            MiniPlayerLayout.minimumDetailHeight,
            accuracy: 0.001
        )
    }

    func testDiagonalResizeRoutesExtraHeightIntoPanel() {
        let size = MiniPlayerResizeGeometry.contentSize(
            requested: NSSize(width: 500, height: 830),
            current: NSSize(width: 420, height: 720)
        )

        XCTAssertEqual(size.width, 500, accuracy: 0.001)
        XCTAssertEqual(size.height, 830, accuracy: 0.001)
    }

    func testCollapsedTracksWidthOnHorizontalEdgeDrag() {
        let size = MiniPlayerResizeGeometry.collapsedSize(
            requested: NSSize(width: 460, height: 420),
            current: NSSize(width: 420, height: 420)
        )

        XCTAssertEqual(size.width, 460, accuracy: 0.001)
        XCTAssertEqual(size.height, 460, accuracy: 0.001)
    }

    func testCollapsedGrowsViaVerticalEdgeDrag() {
        let size = MiniPlayerResizeGeometry.collapsedSize(
            requested: NSSize(width: 420, height: 450),
            current: NSSize(width: 420, height: 420)
        )

        XCTAssertEqual(size.width, 450, accuracy: 0.001)
        XCTAssertEqual(size.height, 450, accuracy: 0.001)
    }

    func testCollapsedShrinksViaVerticalEdgeDrag() {
        let size = MiniPlayerResizeGeometry.collapsedSize(
            requested: NSSize(width: 420, height: 396),
            current: NSSize(width: 420, height: 420)
        )

        XCTAssertEqual(size.width, 396, accuracy: 0.001)
        XCTAssertEqual(size.height, 396, accuracy: 0.001)
    }

    func testCollapsedKeepsMinimumSide() {
        let size = MiniPlayerResizeGeometry.collapsedSize(
            requested: NSSize(width: 420, height: 200),
            current: NSSize(width: 420, height: 420)
        )

        XCTAssertEqual(size.width, MiniPlayerLayout.minimumCompactSide, accuracy: 0.001)
        XCTAssertEqual(size.height, MiniPlayerLayout.minimumCompactSide, accuracy: 0.001)
    }

    func testCollapsedCornerDragTakesDominantAxis() {
        let size = MiniPlayerResizeGeometry.collapsedSize(
            requested: NSSize(width: 380, height: 470),
            current: NSSize(width: 420, height: 420)
        )

        XCTAssertEqual(size.width, 470, accuracy: 0.001)
        XCTAssertEqual(size.height, 470, accuracy: 0.001)
    }
}
