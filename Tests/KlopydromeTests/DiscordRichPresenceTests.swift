import XCTest
@testable import Klopydrome
import NavidromeClient

final class DiscordRichPresenceTests: XCTestCase {
    func testApplicationIDAcceptsOnlyDigits() {
        XCTAssertEqual(DiscordRichPresence.validApplicationID("  123456789  "), "123456789")
        XCTAssertNil(DiscordRichPresence.validApplicationID("client-id"))
        XCTAssertNil(DiscordRichPresence.validApplicationID(""))
    }

    func testDiscordPreferencesRoundTripThroughServerConfig() throws {
        var config = ServerConfig.empty
        config.discordRichPresenceEnabled = true
        config.discordApplicationID = "123456789"
        config.discordShowPaused = false

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ServerConfig.self, from: data)

        XCTAssertTrue(decoded.effectiveDiscordRichPresenceEnabled)
        XCTAssertEqual(decoded.discordApplicationID, "123456789")
        XCTAssertFalse(decoded.effectiveDiscordShowPaused)
    }

    func testExternalArtworkURLRequiresSafeHTTPS() {
        XCTAssertEqual(
            DiscordRichPresenceActivity.externalArtworkURL("https://images.example.com/album.jpg")?.absoluteString,
            "https://images.example.com/album.jpg"
        )
        XCTAssertNil(DiscordRichPresenceActivity.externalArtworkURL("http://images.example.com/album.jpg"))
        XCTAssertNil(DiscordRichPresenceActivity.externalArtworkURL("https://user:password@example.com/album.jpg"))
    }

    func testPlayingActivityContainsTrackProgressAndArtwork() {
        let song = SubsonicSong(
            id: "track", title: "Track", album: "Album", artist: "Artist",
            coverArt: "cover", duration: 240
        )
        let activity = DiscordRichPresenceActivity(
            song: song,
            isPlaying: true,
            currentTime: 30,
            duration: 240,
            artworkURL: URL(string: "https://images.example.com/album.jpg"),
            now: Date(timeIntervalSince1970: 1_000)
        )
        XCTAssertEqual(activity.type, 2)
        XCTAssertEqual(activity.details, "Track")
        XCTAssertEqual(activity.state, "Artist")
        XCTAssertEqual(activity.timestamps, DiscordRichPresenceTimestamps(start: 970, end: 1_210))
        XCTAssertEqual(activity.assets?.largeImage, "https://images.example.com/album.jpg")
    }

    func testPausedActivityDoesNotAdvanceTimer() {
        let song = SubsonicSong(id: "track", title: "Track", duration: 240)
        let activity = DiscordRichPresenceActivity(
            song: song,
            isPlaying: false,
            currentTime: 30,
            duration: 240,
            artworkURL: nil,
            now: Date(timeIntervalSince1970: 1_000)
        )
        XCTAssertNil(activity.timestamps)
        XCTAssertEqual(activity.assets?.largeImage, "icon")
    }

    func testFrameHeaderParsesLittleEndianOpcodeAndLength() {
        var data = Data()
        var opcode = UInt32(1).littleEndian
        var length = UInt32(4).littleEndian
        data.append(Data(bytes: &opcode, count: 4))
        data.append(Data(bytes: &length, count: 4))
        let parsed = DiscordRPCFrame.parseHeader(data)
        XCTAssertEqual(parsed?.opcode, 1)
        XCTAssertEqual(parsed?.length, 4)
        XCTAssertNil(DiscordRPCFrame.parseHeader(Data([1, 2])))
    }

    func testHandshakeReadyClassification() {
        let ready = #"{"cmd":"DISPATCH","evt":"READY","data":{"v":1}}"#
        XCTAssertTrue(DiscordRPCFrame.isReady(Data(ready.utf8)))
        // The SET_ACTIVITY echo carries evt null, not READY.
        let echo = #"{"cmd":"SET_ACTIVITY","data":{},"evt":null,"nonce":"abc"}"#
        XCTAssertFalse(DiscordRPCFrame.isReady(Data(echo.utf8)))
        XCTAssertFalse(DiscordRPCFrame.isError(Data(echo.utf8)))
        // Discord's rejection of an unknown client id is a CLOSE frame, which is
        // classified by opcode; an ERROR payload is a separate RPC error.
        let error = #"{"cmd":"SET_ACTIVITY","evt":"ERROR","data":{"code":4006,"message":"x"}}"#
        XCTAssertTrue(DiscordRPCFrame.isError(Data(error.utf8)))
        XCTAssertFalse(DiscordRPCFrame.isReady(Data(error.utf8)))
        XCTAssertFalse(DiscordRPCFrame.isError(Data("not json".utf8)))
    }

    override func tearDown() {
        super.tearDown()
        UserDefaults.standard.removeObject(forKey: "discordSnoozeUntil")
    }

    @MainActor
    func testSnoozeForCurrentTrackSuppressesPresenceAndResumesOnNextTrack() {
        let app = AppState()
        let song1 = SubsonicSong(id: "snooze-song-1", title: "Song 1", duration: 180)
        let song2 = SubsonicSong(id: "snooze-song-2", title: "Song 2", duration: 200)

        app.player.setQueue([song1, song2], startAt: 0)
        XCTAssertEqual(app.player.currentSong?.id, "snooze-song-1")
        XCTAssertFalse(app.isDiscordSnoozed)

        app.snoozeDiscordForCurrentTrack()
        XCTAssertTrue(app.isDiscordSnoozed)
        XCTAssertEqual(app.discordSnoozeSongID, "snooze-song-1")

        app.player.next()
        XCTAssertEqual(app.player.currentSong?.id, "snooze-song-2")
        app.refreshDiscordRichPresence()
        XCTAssertFalse(app.isDiscordSnoozed)
        XCTAssertNil(app.discordSnoozeSongID)
    }

    @MainActor
    func testSnoozeForCurrentTrackResumesOnTrackEnd() {
        let app = AppState()
        let song = SubsonicSong(id: "snooze-song-end", title: "Song End", duration: 180)

        app.player.setQueue([song], startAt: 0)
        app.snoozeDiscordForCurrentTrack()
        XCTAssertTrue(app.isDiscordSnoozed)

        app.player.onTrackEnded?()
        XCTAssertFalse(app.isDiscordSnoozed)
        XCTAssertNil(app.discordSnoozeSongID)
    }

    @MainActor
    func testTimedSnoozeOverridesTrackSnooze() {
        let app = AppState()
        let song = SubsonicSong(id: "snooze-song-override", title: "Song Override", duration: 180)

        app.player.setQueue([song], startAt: 0)
        app.snoozeDiscordForCurrentTrack()
        XCTAssertEqual(app.discordSnoozeSongID, "snooze-song-override")

        app.snoozeDiscord(for: 3600)
        XCTAssertNil(app.discordSnoozeSongID)
        XCTAssertTrue(app.isDiscordSnoozed)
        XCTAssertNotNil(app.discordSnoozeUntil)

        app.resumeDiscordSnooze()
        XCTAssertFalse(app.isDiscordSnoozed)
        XCTAssertNil(app.discordSnoozeUntil)
    }
}
