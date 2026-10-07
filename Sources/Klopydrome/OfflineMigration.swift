import Foundation
import NavidromeClient

struct OfflineMigration {
    static func migrateIfNeeded(cacheRoot: URL, repository: any OfflineRepository) async {
        let songsURL = cacheRoot.appendingPathComponent("offline-songs.json")
        let snapshotURL = cacheRoot.appendingPathComponent("offline-library.json")

        let fileManager = FileManager.default
        let hasSongs = fileManager.fileExists(atPath: songsURL.path)
        let hasSnapshot = fileManager.fileExists(atPath: snapshotURL.path)

        guard hasSongs || hasSnapshot else { return }

        do {
            if hasSongs,
               let songData = try? Data(contentsOf: songsURL),
               let songs = try? JSONDecoder().decode([SubsonicSong].self, from: songData) {
                for song in songs {
                    try await repository.saveTrack(song)
                }
            }

            if hasSnapshot,
               let snapData = try? Data(contentsOf: snapshotURL),
               let snapshot = try? JSONDecoder().decode(LegacyOfflineLibrarySnapshot.self, from: snapData) {
                if !snapshot.playlists.isEmpty {
                    try await repository.savePlaylists(snapshot.playlists)
                }
                for (_, detail) in snapshot.albumDetails {
                    try await repository.saveAlbumDetail(detail)
                }
                for (_, detail) in snapshot.playlistDetails {
                    try await repository.savePlaylistDetail(detail)
                }
            }

            try? fileManager.removeItem(at: songsURL)
            try? fileManager.removeItem(at: snapshotURL)
        } catch {
            // Retain legacy files if migration errors
        }
    }
}

struct LegacyOfflineLibrarySnapshot: Codable {
    var albums: [SubsonicAlbum] = []
    var playlists: [PlaylistSummary] = []
    var albumDetails: [String: AlbumDetail] = [:]
    var playlistDetails: [String: PlaylistDetail] = [:]
}
