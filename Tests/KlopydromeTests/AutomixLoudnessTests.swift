import XCTest
@testable import Klopydrome

final class AutomixLoudnessTests: XCTestCase {
    func testDecibelConversionUsesAmplitudeScale() {
        XCTAssertEqual(AutomixLoudness.linearGain(forDecibels: 0), 1, accuracy: 0.000_001)
        XCTAssertEqual(
            AutomixLoudness.linearGain(forDecibels: AutomixLoudness.crossfadeHeadroomDB),
            0.707_946,
            accuracy: 0.000_001
        )
    }

    func testMPVOptionsUseTrackGainAndConservativeHeadroom() {
        let options = Dictionary(uniqueKeysWithValues: AutomixLoudness.mpvOptions(
            replayGainMode: .track,
            preampDB: AutomixLoudness.crossfadeHeadroomDB,
            silenceTrimMode: .off
        ))
        XCTAssertEqual(options["replaygain"], "track")
        XCTAssertEqual(options["replaygain-preamp"], "-3")
        XCTAssertEqual(options["replaygain-fallback"], "-3")
        XCTAssertEqual(options["replaygain-clip"], "no")
        XCTAssertNil(options["af"])
    }

    func testMPVOptionsHonorAlbumModeAndPreamp() {
        let options = Dictionary(uniqueKeysWithValues: AutomixLoudness.mpvOptions(
            replayGainMode: .album,
            preampDB: -3.5,
            silenceTrimMode: .off
        ))
        XCTAssertEqual(options["replaygain"], "album")
        XCTAssertEqual(options["replaygain-preamp"], "-3.5")
        XCTAssertEqual(options["replaygain-fallback"], "-3.5")
        XCTAssertNil(options["af"])
    }

    func testMPVOptionsDisableGainOmitsClip() {
        let options = Dictionary(uniqueKeysWithValues: AutomixLoudness.mpvOptions(
            replayGainMode: .off,
            preampDB: 0,
            silenceTrimMode: .off
        ))
        XCTAssertEqual(options["replaygain"], "no")
        XCTAssertEqual(options["replaygain-preamp"], "0")
        XCTAssertEqual(options["replaygain-fallback"], "0")
    }

    func testPreampClampsToSupportedRange() {
        XCTAssertEqual(AutomixLoudness.clampPreamp(20), 12)
        XCTAssertEqual(AutomixLoudness.clampPreamp(-20), -12)
        XCTAssertEqual(AutomixLoudness.clampPreamp(-3), -3)
    }

    func testMPVOptionsAttachSilenceTrimFilter() {
        let options = Dictionary(uniqueKeysWithValues: AutomixLoudness.mpvOptions(
            replayGainMode: .track,
            preampDB: -3,
            silenceTrimMode: .strong
        ))
        XCTAssertEqual(options["af"], SilenceTrimMode.strong.mpvAudioFilterOption())
    }

    func testSilenceTrimFilterOptionTrimsOnlyTrackEnd() {
        XCTAssertNil(SilenceTrimMode.off.mpvAudioFilterOption())
        XCTAssertNotNil(SilenceTrimMode.light.mpvAudioFilterOption())
        XCTAssertNotNil(SilenceTrimMode.strong.mpvAudioFilterOption())
        for mode in [SilenceTrimMode.light, .strong] {
            let option = mode.mpvAudioFilterOption()
            XCTAssertTrue(option?.hasPrefix("lavfi=[silenceremove=") ?? false)
            XCTAssertTrue(option?.contains("stop_periods=1") ?? false)
            XCTAssertTrue(option?.hasSuffix("]") ?? false)
        }
    }
}
