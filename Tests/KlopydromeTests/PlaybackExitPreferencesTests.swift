import XCTest
@testable import Klopydrome

final class PlaybackExitPreferencesTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "PlaybackExitPreferencesTests")!
        defaults.removePersistentDomain(forName: "PlaybackExitPreferencesTests")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "PlaybackExitPreferencesTests")
        defaults = nil
        super.tearDown()
    }

    func testMissingPreferencesUseSafeDefaults() {
        let preferences = PlaybackExitPreferences.load(from: defaults)

        XCTAssertEqual(preferences.volume, 1, accuracy: 0.0001)
        XCTAssertFalse(preferences.shuffleEnabled)
    }

    func testSaveRoundTripsVolumeAndShuffle() {
        PlaybackExitPreferences(volume: 0.35, shuffleEnabled: true).save(to: defaults)

        let preferences = PlaybackExitPreferences.load(from: defaults)
        XCTAssertEqual(preferences.volume, 0.35, accuracy: 0.0001)
        XCTAssertTrue(preferences.shuffleEnabled)
    }

    func testInvalidStoredVolumeIsClamped() {
        defaults.set(4.0, forKey: PlaybackExitPreferences.volumeKey)
        defaults.set(true, forKey: PlaybackExitPreferences.shuffleEnabledKey)

        let preferences = PlaybackExitPreferences.load(from: defaults)
        XCTAssertEqual(preferences.volume, 1, accuracy: 0.0001)
        XCTAssertTrue(preferences.shuffleEnabled)
    }
}
