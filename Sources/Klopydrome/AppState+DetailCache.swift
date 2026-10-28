import Foundation
import NavidromeClient

// MARK: - Stale-While-Revalidate Album, Playlist and Artist Detail Disk Caching

extension AppState {
    private static func albumDetailMetadataKey(for albumID: String) -> String {
        "detail_album_\(albumID)"
    }

    private static func playlistDetailMetadataKey(for playlistID: String) -> String {
        "detail_playlist_\(playlistID)"
    }

    private static func artistDetailMetadataKey(for artistID: String) -> String {
        "detail_artist_\(artistID)"
    }

    private func readCachedMetadata<T: Decodable>(key: String) async -> T? {
        guard let cache,
              let data = await cache.readData(for: .metadata, key: key) else {
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func writeCachedMetadata<T: Encodable>(_ value: T, key: String) async {
        guard let cache,
              let data = try? JSONEncoder().encode(value) else {
            return
        }
        _ = try? await cache.write(data: data, to: .metadata, key: key)
    }

    /// Reads cached AlbumDetail from in-memory LibraryCache or disk metadata store.
    func cachedAlbumDetail(for albumID: String) async -> AlbumDetail? {
        if let memory = library.albumDetails[albumID] {
            return memory
        }
        guard let detail: AlbumDetail = await readCachedMetadata(key: Self.albumDetailMetadataKey(for: albumID)) else {
            return nil
        }
        library.albumDetails[albumID] = detail
        return detail
    }

    /// Caches AlbumDetail both in memory and to disk metadata store.
    func persistAlbumDetail(_ detail: AlbumDetail) async {
        library.albumDetails[detail.id] = detail
        library.recordAlbumDetailAccess(detail.id)
        await writeCachedMetadata(detail, key: Self.albumDetailMetadataKey(for: detail.id))
    }

    /// Reads cached PlaylistDetail from disk metadata store.
    func cachedPlaylistDetailFromDisk(for playlistID: String) async -> PlaylistDetail? {
        await readCachedMetadata(key: Self.playlistDetailMetadataKey(for: playlistID))
    }

    /// Persists PlaylistDetail to disk metadata store.
    func persistPlaylistDetailToDisk(_ detail: PlaylistDetail) async {
        await writeCachedMetadata(detail, key: Self.playlistDetailMetadataKey(for: detail.id))
    }

    /// Reads cached ArtistDetail from in-memory LibraryCache or disk metadata store.
    func cachedArtistDetail(for artistID: String) async -> ArtistDetail? {
        if let memory = library.artistDetails[artistID] {
            return memory
        }
        guard let detail: ArtistDetail = await readCachedMetadata(
            key: Self.artistDetailMetadataKey(for: artistID)
        ) else {
            return nil
        }
        library.artistDetails[artistID] = detail
        return detail
    }

    /// Caches ArtistDetail both in memory and to disk metadata store.
    func persistArtistDetail(_ detail: ArtistDetail) async {
        library.artistDetails[detail.id] = detail
        library.recordArtistDetailAccess(detail.id)
        await writeCachedMetadata(detail, key: Self.artistDetailMetadataKey(for: detail.id))
    }
}
