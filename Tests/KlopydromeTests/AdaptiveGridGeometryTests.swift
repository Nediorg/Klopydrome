import XCTest
@testable import Klopydrome

final class AdaptiveGridGeometryTests: XCTestCase {
    func testStandardWidthCalculatesProperColumnsAndCardWidth() {
        // 800 available width, 180 minCard, 16 gap
        // (800 + 16) / (180 + 16) = 816 / 196 = 4 columns
        // (800 - (3 * 16)) / 4 = 752 / 4 = 188 cardWidth
        let grid = AdaptiveGridGeometry(availableWidth: 800, minCard: 180, gap: 16)
        XCTAssertEqual(grid.columnCount, 4)
        XCTAssertEqual(grid.cardWidth, 188)
        XCTAssertEqual(grid.columns.count, 4)
    }

    func testNarrowWidthEnforcesAtLeastOneColumn() {
        let grid = AdaptiveGridGeometry(availableWidth: 120, minCard: 180, gap: 16)
        XCTAssertEqual(grid.columnCount, 1)
        XCTAssertEqual(grid.cardWidth, 120)
        XCTAssertEqual(grid.columns.count, 1)
    }

    func testExactFitCalculatesExpectedValues() {
        // 3 cards of 180 with 2 gaps of 20 = 540 + 40 = 580
        let grid = AdaptiveGridGeometry(availableWidth: 580, minCard: 180, gap: 20)
        XCTAssertEqual(grid.columnCount, 3)
        XCTAssertEqual(grid.cardWidth, 180)
        XCTAssertEqual(grid.columns.count, 3)
    }
}
