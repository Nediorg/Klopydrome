import XCTest
@testable import Klopydrome

final class PlayerLCDLayoutTests: XCTestCase {

    func testShortTextRemainsCenteredRelativeToFullLCD() {
        let lane = PlayerLCDMetrics.titleLane(isHovered: false)
        let placement = PlayerLCDMetrics.placement(lcdWidth: 360, textWidth: 100, lane: lane)

        XCTAssertFalse(placement.isOverflowing)
        XCTAssertEqual(placement.leadingOffset, 130, accuracy: 0.001)
    }

    func testHoveredSubtitleClearsElapsedAndRemainingTimestampsSymmetrically() {
        let lane = PlayerLCDMetrics.subtitleLane(
            isHovered: true,
            elapsedWidth: 22,
            remainingWidth: 26
        )

        let expectedLeading = PlayerLCDMetrics.coverWidth
            + PlayerLCDMetrics.timeHorizontalPadding
            + 22
            + PlayerLCDMetrics.timeToSubtitleGap
        let expectedTrailing = PlayerLCDMetrics.timeHorizontalPadding
            + 26
            + PlayerLCDMetrics.timeToSubtitleGap

        XCTAssertEqual(lane.minLeading, expectedLeading, accuracy: 0.001)
        XCTAssertEqual(lane.minTrailing, expectedTrailing, accuracy: 0.001)
    }

    func testMediumSubtitleShiftsRightIntoUnusedSpaceInsteadOfOverlappingElapsedTime() {
        let lcdWidth: CGFloat = 340
        let lane = PlayerLCDMetrics.subtitleLane(
            isHovered: true,
            elapsedWidth: 22,
            remainingWidth: 26
        )
        // Centered origin for 210pt text would be (340 - 210)/2 = 65pt, which overlaps elapsed time (ends at 76pt).
        // Available span is 340 - 76 - 38 = 226pt, so text fits by shifting right to 76pt!
        let placement = PlayerLCDMetrics.placement(lcdWidth: lcdWidth, textWidth: 210, lane: lane)

        XCTAssertFalse(placement.isOverflowing)
        XCTAssertEqual(placement.leadingOffset, lane.minLeading, accuracy: 0.001)
        XCTAssertLessThanOrEqual(placement.leadingOffset + 210, lcdWidth - lane.minTrailing)
    }

    func testLongSubtitleUsesFullAvailableSpanBetweenTimestampsWithoutOverlap() {
        let lcdWidth: CGFloat = 340
        let lane = PlayerLCDMetrics.subtitleLane(
            isHovered: true,
            elapsedWidth: 34,
            remainingWidth: 38
        )
        let placement = PlayerLCDMetrics.placement(lcdWidth: lcdWidth, textWidth: 320, lane: lane)

        XCTAssertTrue(placement.isOverflowing)
        XCTAssertEqual(placement.leadingOffset, lane.minLeading, accuracy: 0.001)
        XCTAssertEqual(
            placement.availableWidth,
            lcdWidth - lane.minLeading - lane.minTrailing,
            accuracy: 0.001
        )
    }

    func testTitleTrailingClearanceExceedsControlsWidthInBothStates() {
        let resting = PlayerLCDMetrics.titleLane(isHovered: false)
        let hovered = PlayerLCDMetrics.titleLane(isHovered: true)

        XCTAssertGreaterThan(resting.minTrailing, PlayerLCDMetrics.unhoveredControlsWidth)
        XCTAssertGreaterThan(hovered.minTrailing, PlayerLCDMetrics.hoveredControlsWidth)
        XCTAssertEqual(PlayerLCDMetrics.controlsSpacing, 0)
    }

    func testMarqueeBounceProgressesHoldsAndReturnsCleanly() {
        let distance: CGFloat = 90
        let leg = PlayerLCDMetrics.marqueeLegDuration(distance: distance)
        XCTAssertEqual(PlayerLCDMetrics.marqueeStartDelay, 3.0, accuracy: 0.001)
        XCTAssertEqual(leg, 3.0, accuracy: 0.001)

        XCTAssertEqual(PlayerLCDMetrics.marqueeOffset(elapsed: 0, distance: distance), 0, accuracy: 0.001)
        XCTAssertEqual(PlayerLCDMetrics.marqueeOffset(elapsed: leg / 2, distance: distance), 45, accuracy: 0.001)
        XCTAssertEqual(
            PlayerLCDMetrics.marqueeOffset(elapsed: leg + 0.5, distance: distance),
            distance,
            accuracy: 0.001
        )
        let midReturn = leg + PlayerLCDMetrics.marqueeEndPause + leg / 2
        XCTAssertEqual(PlayerLCDMetrics.marqueeOffset(elapsed: midReturn, distance: distance), 45, accuracy: 0.001)
        let startPause = 2 * leg + PlayerLCDMetrics.marqueeEndPause + 1.0
        XCTAssertEqual(PlayerLCDMetrics.marqueeOffset(elapsed: startPause, distance: distance), 0, accuracy: 0.001)
    }

    func testMarqueeDistanceAndLegDuration() {
        XCTAssertEqual(PlayerLCDMetrics.marqueeDistance(textWidth: 120, availableWidth: 200), 0)
        XCTAssertEqual(PlayerLCDMetrics.marqueeLegDuration(distance: 0), 0)

        let distance = PlayerLCDMetrics.marqueeDistance(textWidth: 260, availableWidth: 200)
        XCTAssertEqual(distance, 60, accuracy: 0.001)
        XCTAssertEqual(PlayerLCDMetrics.marqueeLegDuration(distance: distance), 2.0, accuracy: 0.001)
        XCTAssertEqual(PlayerLCDMetrics.marqueeLegDuration(distance: 6), 1.0, accuracy: 0.001)
    }
}
