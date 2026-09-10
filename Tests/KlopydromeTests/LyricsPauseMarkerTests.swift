import XCTest
@testable import Klopydrome

final class LyricsPauseMarkerTests: XCTestCase {
    /// A timestamped blank LRC row is retained for the progressive pause marker.
    func testLrcPreservesTimestampedBlankLineAsPause() {
        let lines = LrcTextParser.parse("[00:10.00]first\n[00:12.00]\n[00:14.00]second")
        XCTAssertEqual(lines.map(\.start), [10_000, 12_000, 14_000])
        XCTAssertEqual(lines.map(\.value), ["first", "", "second"])
    }

    // MARK: Pause marker progress

    func testPauseMarkerProgressClampsToPauseBounds() {
        XCTAssertEqual(LyricsPauseMarker.progress(at: 8, from: 10, until: 20), 0)
        XCTAssertEqual(LyricsPauseMarker.progress(at: 15, from: 10, until: 20), 0.5)
        XCTAssertEqual(LyricsPauseMarker.progress(at: 25, from: 10, until: 20), 1)
    }

    func testPauseMarkerProgressHandlesEmptyInterval() {
        XCTAssertEqual(LyricsPauseMarker.progress(at: 9, from: 10, until: 10), 0)
        XCTAssertEqual(LyricsPauseMarker.progress(at: 10, from: 10, until: 10), 1)
    }

    func testPauseMarkerFillResetsAfterSilenceEnds() {
        XCTAssertEqual(LyricsPauseMarker.fillProgress(for: 0), 0)
        XCTAssertEqual(LyricsPauseMarker.fillProgress(for: 0.5), 0.5)
        XCTAssertEqual(LyricsPauseMarker.fillProgress(for: 1), 0)
    }

}
