import XCTest
@testable import Klopydrome
import NavidromeClient
import SwiftData

extension SwiftDataOfflineRepositoryTests {

    func testUndownloadedAlbumTracksDoNotCreateOfflineTrackEntities() async throws {
        let undownloaded = SubsonicSong(
            id: "track-ghost",
            title: "Ghost Track",
            artist: "Ghost Artist",
            track: 3,
            duration: 180,
            albumId: "album-ghost"
        )
        let detail = AlbumDetail(
            id: "album-ghost",
            name: "Ghost Album",
            songCount: 1,
            song: [undownloaded]
        )
        try await repository.saveAlbumDetail(detail)

        let downloaded = try await repository.fetchDownloadedTracks()
        XCTAssertTrue(downloaded.isEmpty, "No OfflineTrack should be marked downloaded")

        let trackCount = try await repository.fetchTrackCount()
        XCTAssertEqual(trackCount, 0, "Undownloaded album tracks must not create any OfflineTrack rows in SwiftData")

        let fetched = try await repository.fetchAlbumDetail(id: "album-ghost")
        XCTAssertEqual(fetched?.song?.count, 1)
        XCTAssertEqual(fetched?.song?.first?.id, "track-ghost")
        XCTAssertEqual(fetched?.song?.first?.title, "Ghost Track")
    }

    func testTrackDeletionNullifiesPlaylistEntryInsteadOfCascading() async throws {
        let song = SubsonicSong(id: "track-persist", title: "Keep In Playlist", duration: 200)
        try await repository.saveTrack(song)

        let playlist = PlaylistDetail(id: "pl-safe", name: "Safe Playlist", entry: [song])
        try await repository.savePlaylistDetail(playlist)

        let beforeDeleteCount = try await repository.fetchTrackCount()
        XCTAssertEqual(beforeDeleteCount, 1)

        // Remove the downloaded track
        try await repository.removeTrack(id: "track-persist")

        // Track must be completely removed from SwiftData
        let afterDeleteCount = try await repository.fetchTrackCount()
        XCTAssertEqual(afterDeleteCount, 0, "OfflineTrack entity must be completely deleted")

        // Playlist entry should still exist with fallback metadata
        let fetched = try await repository.fetchPlaylistDetail(id: "pl-safe")
        XCTAssertEqual(fetched?.entry?.count, 1)
        XCTAssertEqual(fetched?.entry?.first?.id, "track-persist")
        XCTAssertEqual(fetched?.entry?.first?.title, "Keep In Playlist")

        let entries = try await repository.fetchPlaylistEntries(playlistID: "pl-safe")
        XCTAssertEqual(entries.count, 1)
        XCTAssertFalse(entries.first?.isTrackLinked ?? true, "Playlist entry track relationship must be nullified")
    }

    func testMixedDownloadedAndUndownloadedTracksInAlbumAndPlaylist() async throws {
        let downloadedSong = SubsonicSong(
            id: "track-dl",
            title: "Downloaded Song",
            artist: "Artist A",
            track: 1,
            duration: 210,
            albumId: "album-mix"
        )
        let undownloadedSong = SubsonicSong(
            id: "track-stream",
            title: "Streaming Song",
            artist: "Artist A",
            track: 2,
            duration: 195,
            albumId: "album-mix"
        )

        try await repository.saveTrack(downloadedSong)

        let albumDetail = AlbumDetail(
            id: "album-mix",
            name: "Mixed Album",
            songCount: 2,
            song: [downloadedSong, undownloadedSong]
        )
        try await repository.saveAlbumDetail(albumDetail)

        let playlistDetail = PlaylistDetail(
            id: "pl-mix",
            name: "Mixed Playlist",
            songCount: 2,
            entry: [downloadedSong, undownloadedSong]
        )
        try await repository.savePlaylistDetail(playlistDetail)

        // Only 1 OfflineTrack should exist in SwiftData
        let trackCount = try await repository.fetchTrackCount()
        XCTAssertEqual(trackCount, 1)

        // Fetching album detail reconstructs both in correct order
        let fetchedAlbum = try await repository.fetchAlbumDetail(id: "album-mix")
        XCTAssertEqual(fetchedAlbum?.song?.count, 2)
        XCTAssertEqual(fetchedAlbum?.song?[0].id, "track-dl")
        XCTAssertEqual(fetchedAlbum?.song?[1].id, "track-stream")

        // Fetching playlist detail reconstructs both in correct order
        let fetchedPlaylist = try await repository.fetchPlaylistDetail(id: "pl-mix")
        XCTAssertEqual(fetchedPlaylist?.entry?.count, 2)
        XCTAssertEqual(fetchedPlaylist?.entry?[0].id, "track-dl")
        XCTAssertEqual(fetchedPlaylist?.entry?[1].id, "track-stream")
    }

    func testLargePlaylistSaveAndFetchPerformance() async throws {
        let songs = (0..<1000).map { idx in
            SubsonicSong(
                id: "song-\(idx)",
                title: "Track \(idx)",
                album: "Album \(idx / 10)",
                artist: "Artist \(idx / 20)",
                track: (idx % 10) + 1,
                year: 2024,
                duration: 180 + (idx % 60)
            )
        }

        let detail = PlaylistDetail(
            id: "large-playlist-1000",
            name: "1000 Tracks Playlist",
            songCount: 1000,
            duration: 200000,
            entry: songs
        )

        let startSave = CACurrentMediaTime()
        try await repository.savePlaylistDetail(detail)
        let saveDuration = CACurrentMediaTime() - startSave

        let startFetch = CACurrentMediaTime()
        let fetched = try await repository.fetchPlaylistDetail(id: "large-playlist-1000")
        let fetchDuration = CACurrentMediaTime() - startFetch

        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.entry?.count, 1000)
        XCTAssertEqual(fetched?.entry?.first?.id, "song-0")
        XCTAssertEqual(fetched?.entry?.last?.id, "song-999")

        // Saving and fetching via tracksSummaryData should be very fast
        XCTAssertLessThan(saveDuration, 0.5, "Save of 1,000 songs should complete quickly")
        XCTAssertLessThan(fetchDuration, 0.2, "Fetch of 1,000 songs should complete quickly")
    }

    func testPlaylistTracksDynamicDownloadAndRemoval() async throws {
        let undownloaded = SubsonicSong(
            id: "track-stream-later",
            title: "Later Song",
            artist: "Artist X",
            track: 1,
            duration: 200,
            albumId: "album-x"
        )

        let playlist = PlaylistDetail(
            id: "pl-dynamic",
            name: "Dynamic Playlist",
            songCount: 1,
            entry: [undownloaded]
        )
        try await repository.savePlaylistDetail(playlist)

        // Initially undownloaded
        let initialFetch = try await repository.fetchPlaylistDetail(id: "pl-dynamic")
        XCTAssertEqual(initialFetch?.entry?.count, 1)
        XCTAssertEqual(initialFetch?.entry?.first?.id, "track-stream-later")

        // Download the track later
        try await repository.saveTrack(undownloaded)

        // Fetching playlist should now reflect that it is downloaded
        let fetchAfterDownload = try await repository.fetchPlaylistDetail(id: "pl-dynamic")
        XCTAssertEqual(fetchAfterDownload?.entry?.count, 1)
        XCTAssertEqual(fetchAfterDownload?.entry?.first?.id, "track-stream-later")

        // Now remove downloaded track from disk
        try await repository.removeTrack(id: "track-stream-later")

        // Fetching playlist should still preserve the track using summary metadata
        let fetchAfterRemove = try await repository.fetchPlaylistDetail(id: "pl-dynamic")
        XCTAssertEqual(fetchAfterRemove?.entry?.count, 1)
        XCTAssertEqual(fetchAfterRemove?.entry?.first?.id, "track-stream-later")
        XCTAssertEqual(fetchAfterRemove?.entry?.first?.title, "Later Song")
    }
}
