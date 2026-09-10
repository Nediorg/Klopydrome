import Foundation
import NavidromeClient
import Observation

/// Holds the already-fetched data of each library tab. Tab views read from
/// here instead of fetching on every appearance, so switching tabs shows
/// content instantly and refreshes in the background.
@MainActor
@Observable
final class LibraryCache {
    var albums: [SubsonicAlbum] = []
    var albumsAllLoaded = false
    var recentAlbums: [SubsonicAlbum] = []
    var recentAllLoaded = false
    var artistIndexes: [ArtistIndex] = []
    var favoritesArtists: [Artist] = []
    var favoritesAlbums: [SubsonicAlbum] = []
    var favoritesSongs: [SubsonicSong] = []
    var playlists: [PlaylistSummary] = []
    /// Full entries for playlists visited during this session. A manifest refresh
    /// invalidates a detail only when Navidrome reports a changed timestamp or
    /// song count, so returning to a large playlist avoids another full payload.
    var playlistDetails: [String: PlaylistDetail] = [:]
    var songs: [SubsonicSong] = []
    var homeShelves: [AlbumListType: [SubsonicAlbum]] = [:]
    var homeShelfErrors: [AlbumListType: String] = [:]

    /// Whether each store has been fetched at least once. Tab views gate their
    /// `.task` loads on these flags, so returning to an already-visited tab is
    /// instant (no server round-trip, no scroll reset); `.refreshable` and the
    /// per-shelf refresh button still force a reload. A genuine empty library is
    /// handled too: an empty-but-loaded store never re-fetches.
    var albumsLoaded = false
    var recentAlbumsLoaded = false
    var artistIndexesLoaded = false
    var favoritesLoaded = false
    var playlistsLoaded = false
    var songsLoaded = false
    var homeShelvesLoaded = false
}
