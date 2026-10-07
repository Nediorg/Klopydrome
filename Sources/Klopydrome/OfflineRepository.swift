import Foundation
import NavidromeClient

public protocol OfflineRepository: Sendable {
    func saveTrack(_ song: SubsonicSong) async throws
    func removeTrack(id: String) async throws
    func fetchDownloadedTracks() async throws -> [SubsonicSong]
    func saveAlbumDetail(_ detail: AlbumDetail) async throws
    func fetchAlbumDetail(id: String) async throws -> AlbumDetail?
    func savePlaylists(_ playlists: [PlaylistSummary]) async throws
    func savePlaylistDetail(_ detail: PlaylistDetail) async throws
    func fetchPlaylistDetail(id: String) async throws -> PlaylistDetail?
    func fetchAlbums() async throws -> [SubsonicAlbum]
    func fetchPlaylists() async throws -> [PlaylistSummary]
    func fetchPlaylists(matchingDownloadedTrackIDs downloadedIDs: Set<String>) async throws -> [PlaylistSummary]
    func fetchArtists() async throws -> [Artist]
    func clearAll() async throws
}
