import Foundation
import NavidromeClient

struct OfflineLibrarySnapshot: Codable, Equatable {
    var albums: [SubsonicAlbum] = []
    var playlists: [PlaylistSummary] = []
    var albumDetails: [String: AlbumDetail] = [:]
    var playlistDetails: [String: PlaylistDetail] = [:]
}

struct OfflineLibraryStore {
    private let songsURL: URL
    private let snapshotURL: URL

    init(cache: CacheManager) {
        let root = cache.directory(for: .streams).deletingLastPathComponent()
        songsURL = root.appendingPathComponent("offline-songs.json")
        snapshotURL = root.appendingPathComponent("offline-library.json")
    }

    func load() -> [SubsonicSong] {
        decode([SubsonicSong].self, from: songsURL) ?? []
    }

    func save(_ songs: [SubsonicSong]) {
        encode(songs, to: songsURL)
    }

    func loadSnapshot() -> OfflineLibrarySnapshot {
        decode(OfflineLibrarySnapshot.self, from: snapshotURL) ?? OfflineLibrarySnapshot()
    }

    func saveSnapshot(_ snapshot: OfflineLibrarySnapshot) {
        encode(snapshot, to: snapshotURL)
    }

    func clear() {
        try? FileManager.default.removeItem(at: songsURL)
        try? FileManager.default.removeItem(at: snapshotURL)
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from url: URL) -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    private func encode<Value: Encodable>(_ value: Value, to url: URL) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
