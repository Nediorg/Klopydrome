import Foundation
import NavidromeClient

// MARK: - Stale-While-Revalidate Album and Playlist Detail Disk Caching

extension AppState {
    private static func albumDetailMetadataKey(for albumID: String) -> String {
        "detail_album_\(albumID)"
    }

    private static func playlistDetailMetadataKey(for playlistID: String) -> String {
        "detail_playlist_\(playlistID)"
    }

    /// Reads cached AlbumDetail from in-memory LibraryCache or disk metadata store.
    func cachedAlbumDetail(for albumID: String) async -> AlbumDetail? {
        if let memory = library.albumDetails[albumID] {
            return memory
        }
        guard let cache,
              let data = await cache.readData(for: .metadata, key: Self.albumDetailMetadataKey(for: albumID)),
              let detail = try? JSONDecoder().decode(AlbumDetail.self, from: data) else {
            return nil
        }
        library.albumDetails[albumID] = detail
        return detail
    }

    /// Caches AlbumDetail both in memory and to disk metadata store.
    func persistAlbumDetail(_ detail: AlbumDetail) async {
        library.albumDetails[detail.id] = detail
        guard let cache else { return }
        if let data = try? JSONEncoder().encode(detail) {
            _ = try? await cache.write(data: data, to: .metadata, key: Self.albumDetailMetadataKey(for: detail.id))
        }
    }

    /// Reads cached PlaylistDetail from disk metadata store.
    func cachedPlaylistDetailFromDisk(for playlistID: String) async -> PlaylistDetail? {
        guard let cache,
              let data = await cache.readData(for: .metadata, key: Self.playlistDetailMetadataKey(for: playlistID)),
              let detail = try? JSONDecoder().decode(PlaylistDetail.self, from: data) else {
            return nil
        }
        return detail
    }

    /// Persists PlaylistDetail to disk metadata store.
    func persistPlaylistDetailToDisk(_ detail: PlaylistDetail) async {
        guard let cache else { return }
        if let data = try? JSONEncoder().encode(detail) {
            _ = try? await cache.write(data: data, to: .metadata, key: Self.playlistDetailMetadataKey(for: detail.id))
        }
    }
}
