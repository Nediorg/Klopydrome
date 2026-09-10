import XCTest
@testable import Klopydrome

final class PlaybackVolumeTests: XCTestCase {
    func testOutputGainUsesQuietControllableLowEnd() {
        XCTAssertEqual(PlaybackVolume.outputGain(for: 0), 0)
        XCTAssertEqual(PlaybackVolume.outputGain(for: 1), 1)
        XCTAssertEqual(PlaybackVolume.outputGain(for: 0.05), 0.009_625, accuracy: 0.000_001)
        XCTAssertEqual(PlaybackVolume.outputGain(for: 0.10), 0.0235, accuracy: 0.000_001)
        XCTAssertEqual(PlaybackVolume.outputGain(for: 0.15), 0.041_625, accuracy: 0.000_001)
        XCTAssertGreaterThan(PlaybackVolume.outputGain(for: 0.05), 0)
        XCTAssertGreaterThan(PlaybackVolume.outputGain(for: 0.10), 0)
        XCTAssertGreaterThan(PlaybackVolume.outputGain(for: 0.15), 0)
    }

    func testMPVControlCompensatesForItsCubicGainCurve() {
        for control: Float in [0, 0.05, 0.10, 0.15, 0.5, 1] {
            let outputGain = PlaybackVolume.outputGain(for: control)
            let mpvControl = PlaybackVolume.mpvControl(forOutputGain: outputGain)
            XCTAssertEqual(mpvControl * mpvControl * mpvControl, outputGain, accuracy: 0.000_001)
        }
    }

    func testVolumeMappingsClampOutOfRangeInput() {
        XCTAssertEqual(PlaybackVolume.outputGain(for: -1), 0)
        XCTAssertEqual(PlaybackVolume.outputGain(for: 2), 1)
        XCTAssertEqual(PlaybackVolume.mpvControl(forOutputGain: -1), 0)
        XCTAssertEqual(PlaybackVolume.mpvControl(forOutputGain: 2), 1)
    }
}
