import XCTest
@testable import Klopydrome
import NavidromeClient

final class SwiftDataOfflineRepositoryTests: XCTestCase {
    private var repository: SwiftDataOfflineRepository!

    override func setUp() async throws {
        repository = try SwiftDataOfflineRepository.makeInMemory()
    }

    override func tearDown() async throws {
        try? await repository.clearAll()
        repository = nil
    }

    func testTrackCRUD() async throws {
        let song = SubsonicSong(
            id: "song-1",
            title: "Test Track",
            artist: "Test Artist",
            track: 1,
            year: 2024,
            suffix: "flac",
            duration: 180,
            artistId: "artist-1"
        )

        try await repository.saveTrack(song)

        let tracks = try await repository.fetchDownloadedTracks()
        XCTAssertEqual(tracks.count, 1)
        XCTAssertEqual(tracks.first?.id, "song-1")
        XCTAssertEqual(tracks.first?.title, "Test Track")
        XCTAssertEqual(tracks.first?.artist, "Test Artist")

        try await repository.removeTrack(id: "song-1")
        let afterDelete = try await repository.fetchDownloadedTracks()
        XCTAssertTrue(afterDelete.isEmpty)
    }

    func testAutomaticAlbumAndArtistLink() async throws {
        let song = SubsonicSong(
            id: "track-42",
            album: "Dark Side of the Moon",
            artist: "Pink Floyd",
            albumId: "album-99",
            artistId: "artist-77"
        )

        try await repository.saveTrack(song)

        let albums = try await repository.fetchAlbums()
        XCTAssertEqual(albums.count, 1)
        XCTAssertEqual(albums.first?.id, "album-99")
        XCTAssertEqual(albums.first?.title, "Dark Side of the Moon")

        let artists = try await repository.fetchArtists()
        XCTAssertEqual(artists.count, 1)
        XCTAssertEqual(artists.first?.id, "artist-77")
        XCTAssertEqual(artists.first?.name, "Pink Floyd")
    }

    func testAlbumDetailRoundTrip() async throws {
        let track1 = SubsonicSong(id: "track-1", title: "Track One", track: 1, duration: 120, albumId: "album-1")
        let track2 = SubsonicSong(id: "track-2", title: "Track Two", track: 2, duration: 240, albumId: "album-1")

        try await repository.saveTrack(track1)
        try await repository.saveTrack(track2)

        let detail = AlbumDetail(
            id: "album-1",
            name: "My Great Album",
            artist: "Great Artist",
            artistId: "artist-1",
            songCount: 2,
            duration: 360,
            song: [track1, track2]
        )

        try await repository.saveAlbumDetail(detail)

        let fetched = try await repository.fetchAlbumDetail(id: "album-1")
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.id, "album-1")
        XCTAssertEqual(fetched?.name, "My Great Album")
        XCTAssertEqual(fetched?.song?.count, 2)
    }

    func testPlaylistDetailOrderingAndDuplicates() async throws {
        let songA = SubsonicSong(id: "song-A", title: "Song A", duration: 100)
        let songB = SubsonicSong(id: "song-B", title: "Song B", duration: 200)

        try await repository.saveTrack(songA)
        try await repository.saveTrack(songB)

        let playlistDetail = PlaylistDetail(
            id: "playlist-1",
            name: "Favorites Mix",
            comment: "Custom mix",
            songCount: 3,
            duration: 400,
            entry: [songA, songB, songA]
        )

        try await repository.savePlaylistDetail(playlistDetail)

        let fetched = try await repository.fetchPlaylistDetail(id: "playlist-1")
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.name, "Favorites Mix")
        XCTAssertEqual(fetched?.entry?.count, 3)
        XCTAssertEqual(fetched?.entry?[0].id, "song-A")
        XCTAssertEqual(fetched?.entry?[1].id, "song-B")
        XCTAssertEqual(fetched?.entry?[2].id, "song-A")
    }

    func testPlaylistDetailPreservesFullMetadataForUndownloadedTracks() async throws {
        let song = SubsonicSong(
            id: "undownloaded-1",
            title: "Stairway to Heaven",
            album: "Led Zeppelin IV",
            artist: "Led Zeppelin",
            track: 4,
            year: 1971,
            genre: "Rock",
            coverArt: "cover-lz4",
            duration: 482,
            discNumber: 1
        )

        let playlistDetail = PlaylistDetail(
            id: "playlist-rock",
            name: "Classic Rock",
            entry: [song]
        )

        try await repository.savePlaylistDetail(playlistDetail)

        let downloadedTracks = try await repository.fetchDownloadedTracks()
        XCTAssertTrue(downloadedTracks.isEmpty)

        let fetched = try await repository.fetchPlaylistDetail(id: "playlist-rock")
        XCTAssertNotNil(fetched)
        let firstSong = try XCTUnwrap(fetched?.entry?.first)
        XCTAssertEqual(firstSong.id, "undownloaded-1")
        XCTAssertEqual(firstSong.title, "Stairway to Heaven")
        XCTAssertEqual(firstSong.artist, "Led Zeppelin")
        XCTAssertEqual(firstSong.album, "Led Zeppelin IV")
        XCTAssertEqual(firstSong.track, 4)
        XCTAssertEqual(firstSong.year, 1971)
        XCTAssertEqual(firstSong.genre, "Rock")
        XCTAssertEqual(firstSong.coverArt, "cover-lz4")
        XCTAssertEqual(firstSong.duration, 482)
        XCTAssertEqual(firstSong.discNumber, 1)
    }

    func testAlbumDetailPreservesAllTracksOffline() async throws {
        let track1 = SubsonicSong(id: "track-1", title: "Intro", track: 1, duration: 60, albumId: "album-full")
        let track2 = SubsonicSong(id: "track-2", title: "Main", track: 2, duration: 240, albumId: "album-full")

        try await repository.saveTrack(track1)

        let detail = AlbumDetail(
            id: "album-full",
            name: "Full Album",
            songCount: 2,
            duration: 300,
            song: [track1, track2]
        )
        try await repository.saveAlbumDetail(detail)

        let downloaded = try await repository.fetchDownloadedTracks()
        XCTAssertEqual(downloaded.count, 1)
        XCTAssertEqual(downloaded.first?.id, "track-1")

        let fetched = try await repository.fetchAlbumDetail(id: "album-full")
        let songs = try XCTUnwrap(fetched?.song)
        XCTAssertEqual(songs.count, 2)
        XCTAssertEqual(songs[0].id, "track-1")
        XCTAssertEqual(songs[1].id, "track-2")
        XCTAssertEqual(songs[1].title, "Main")
    }

    func testClearAllRemovesAllEntities() async throws {
        let song = SubsonicSong(id: "track-1", album: "Album", artist: "Artist", albumId: "alb-1", artistId: "art-1")
        try await repository.saveTrack(song)

        try await repository.clearAll()

        let tracks = try await repository.fetchDownloadedTracks()
        let albums = try await repository.fetchAlbums()
        let artists = try await repository.fetchArtists()

        XCTAssertTrue(tracks.isEmpty)
        XCTAssertTrue(albums.isEmpty)
        XCTAssertTrue(artists.isEmpty)
    }

    func testFetchPlaylistsMatchingDownloadedTracks() async throws {
        let pl1 = PlaylistDetail(
            id: "pl-1",
            name: "Summer Vibes",
            entry: [
                SubsonicSong(id: "song-1", title: "Song 1"),
                SubsonicSong(id: "song-2", title: "Song 2")
            ]
        )
        let pl2 = PlaylistDetail(
            id: "pl-2",
            name: "Winter Chill",
            entry: [
                SubsonicSong(id: "song-3", title: "Song 3")
            ]
        )

        try await repository.savePlaylistDetail(pl1)
        try await repository.savePlaylistDetail(pl2)

        let matchingPl1 = try await repository.fetchPlaylists(matchingDownloadedTrackIDs: ["song-1"])
        XCTAssertEqual(matchingPl1.count, 1)
        XCTAssertEqual(matchingPl1.first?.id, "pl-1")

        let matchingBoth = try await repository.fetchPlaylists(matchingDownloadedTrackIDs: ["song-2", "song-3"])
        XCTAssertEqual(matchingBoth.count, 2)

        let matchingNone = try await repository.fetchPlaylists(matchingDownloadedTrackIDs: ["unknown-song"])
        XCTAssertTrue(matchingNone.isEmpty)
    }

    func testLegacyMigrationImportsDataAndRemovesFiles() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let songsFile = tempDir.appendingPathComponent("offline-songs.json")
        let snapshotFile = tempDir.appendingPathComponent("offline-library.json")

        let song = SubsonicSong(id: "migrated-1", title: "Migrated Song", artist: "Legacy Artist")
        let songsData = try JSONEncoder().encode([song])
        try songsData.write(to: songsFile)

        let album = SubsonicAlbum(id: "migrated-album", title: "Migrated Album")
        let playlist = PlaylistSummary(id: "migrated-playlist", name: "Migrated Playlist")
        let snapshot = LegacyOfflineLibrarySnapshot(
            albums: [album],
            playlists: [playlist],
            albumDetails: [:],
            playlistDetails: [:]
        )
        let snapshotData = try JSONEncoder().encode(snapshot)
        try snapshotData.write(to: snapshotFile)

        await OfflineMigration.migrateIfNeeded(cacheRoot: tempDir, repository: repository)

        let tracks = try await repository.fetchDownloadedTracks()
        XCTAssertEqual(tracks.count, 1)
        XCTAssertEqual(tracks.first?.id, "migrated-1")

        let playlists = try await repository.fetchPlaylists()
        XCTAssertEqual(playlists.count, 1)
        XCTAssertEqual(playlists.first?.id, "migrated-playlist")

        XCTAssertFalse(FileManager.default.fileExists(atPath: songsFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotFile.path))
    }

    func testServerConfigOfflineDefaults() {
        let config = ServerConfig.empty
        XCTAssertTrue(config.effectiveAutoReconnectEnabled)
        XCTAssertFalse(config.effectiveForceOfflineMode)

        var custom = config
        custom.autoReconnectEnabled = false
        custom.forceOfflineMode = true
        XCTAssertFalse(custom.effectiveAutoReconnectEnabled)
        XCTAssertTrue(custom.effectiveForceOfflineMode)
    }
}
