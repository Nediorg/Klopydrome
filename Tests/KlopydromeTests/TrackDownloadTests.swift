import XCTest
@testable import Klopydrome
import NavidromeClient

final class TrackDownloadTests: XCTestCase {
    func testFilenameUsesOriginalTrackPathBeforeMetadataFallback() {
        let song = SubsonicSong(
            id: "song",
            title: "Fallback",
            artist: "Artist",
            suffix: "mp3",
            path: "/library/Artist/Original Track.m4a"
        )

        let filename = TrackDownload.filename(for: song)

        XCTAssertEqual(filename, "Original Track.m4a")
    }

    func testFilenameBuildsSafeFallbackWithTrackSuffix() {
        let song = SubsonicSong(id: "song", title: "Summer: Night", artist: "The/Artist", suffix: "opus")

        let filename = TrackDownload.filename(for: song)

        XCTAssertEqual(filename, "The-Artist – Summer- Night.opus")
    }

    func testSavePanelSuggestsTrackFilenameAndAllowsFolderChoice() {
        let song = SubsonicSong(id: "song", title: "Track", artist: "Artist", suffix: "flac")

        let panel = TrackDownload.savePanel(for: song)

        XCTAssertEqual(panel.title, "Скачать трек")
        XCTAssertEqual(panel.prompt, "Скачать")
        XCTAssertEqual(panel.nameFieldStringValue, "Artist – Track.flac")
        XCTAssertTrue(panel.canCreateDirectories)
        XCTAssertFalse(panel.isExtensionHidden)
    }

    // MARK: - Original-format checkbox helpers

    private func config(format: String?, maxBitRate: Int) -> ServerConfig {
        var config = ServerConfig.empty
        config.format = format
        config.maxBitRate = maxBitRate
        return config
    }

    func testTranscodeSettingsNilWithoutConfiguredTranscoding() {
        XCTAssertNil(TrackDownload.transcodeSettings(in: config(format: nil, maxBitRate: 0)))
        XCTAssertNil(TrackDownload.transcodeSettings(in: config(format: "  ", maxBitRate: 0)))
    }

    func testTranscodeSettingsReadsFormatAndBitrate() {
        let both = TrackDownload.transcodeSettings(in: config(format: "Opus", maxBitRate: 128))
        XCTAssertEqual(both?.format, "opus")
        XCTAssertEqual(both?.maxBitRate, 128)

        let bitrateOnly = TrackDownload.transcodeSettings(in: config(format: nil, maxBitRate: 320))
        XCTAssertNil(bitrateOnly?.format)
        XCTAssertEqual(bitrateOnly?.maxBitRate, 320)
    }

    func testApplyingFormatSwapsDestinationExtension() {
        XCTAssertEqual(
            TrackDownload.filename("Artist – Track.flac", applyingFormat: "opus"),
            "Artist – Track.opus")
        XCTAssertEqual(
            TrackDownload.filename("Track", applyingFormat: "mp3"),
            "Track.mp3")
    }

    func testApplyingFormatIgnoresMatchingOrMissingCodec() {
        XCTAssertNil(TrackDownload.filename("Artist – Track.flac", applyingFormat: "FLAC"))
        XCTAssertNil(TrackDownload.filename("Artist – Track.flac", applyingFormat: nil))
    }

    @MainActor
    func testOriginalFormatCheckboxDefaultsToOnAndDisablesWithoutTranscoding() {
        let enabled = TrackDownload.originalFormatAccessory(transcodeAvailable: true)
        XCTAssertEqual(enabled.checkbox.state, .on)
        XCTAssertTrue(enabled.checkbox.isEnabled)

        let disabled = TrackDownload.originalFormatAccessory(transcodeAvailable: false)
        XCTAssertFalse(disabled.checkbox.isEnabled)
    }
}
