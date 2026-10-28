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
    private static let maxDetailCacheCapacity = 25

    /// Full entries for playlists visited during this session. A manifest refresh
    /// invalidates a detail only when Navidrome reports a changed timestamp or
    /// song count, so returning to a large playlist avoids another full payload.
    @ObservationIgnored private var playlistDetailOrder: [String] = []
    var playlistDetails: [String: PlaylistDetail] = [:] {
        didSet {
            let currentKeys = Set(playlistDetails.keys)
            playlistDetailOrder.removeAll { !currentKeys.contains($0) }
            for key in playlistDetails.keys where !playlistDetailOrder.contains(key) {
                playlistDetailOrder.append(key)
            }
            while playlistDetailOrder.count > Self.maxDetailCacheCapacity {
                let oldest = playlistDetailOrder.removeFirst()
                playlistDetails.removeValue(forKey: oldest)
            }
        }
    }

    func recordPlaylistDetailAccess(_ id: String) {
        if let index = playlistDetailOrder.firstIndex(of: id) {
            playlistDetailOrder.remove(at: index)
            playlistDetailOrder.append(id)
        }
    }

    /// Full entries for albums visited during this session.
    @ObservationIgnored private var albumDetailOrder: [String] = []
    var albumDetails: [String: AlbumDetail] = [:] {
        didSet {
            let currentKeys = Set(albumDetails.keys)
            albumDetailOrder.removeAll { !currentKeys.contains($0) }
            for key in albumDetails.keys where !albumDetailOrder.contains(key) {
                albumDetailOrder.append(key)
            }
            while albumDetailOrder.count > Self.maxDetailCacheCapacity {
                let oldest = albumDetailOrder.removeFirst()
                albumDetails.removeValue(forKey: oldest)
            }
        }
    }

    func recordAlbumDetailAccess(_ id: String) {
        if let index = albumDetailOrder.firstIndex(of: id) {
            albumDetailOrder.remove(at: index)
            albumDetailOrder.append(id)
        }
    }

    /// Full entries for artists visited during this session.
    @ObservationIgnored private var artistDetailOrder: [String] = []
    var artistDetails: [String: ArtistDetail] = [:] {
        didSet {
            let currentKeys = Set(artistDetails.keys)
            artistDetailOrder.removeAll { !currentKeys.contains($0) }
            for key in artistDetails.keys where !artistDetailOrder.contains(key) {
                artistDetailOrder.append(key)
            }
            while artistDetailOrder.count > Self.maxDetailCacheCapacity {
                let oldest = artistDetailOrder.removeFirst()
                artistDetails.removeValue(forKey: oldest)
            }
        }
    }

    func recordArtistDetailAccess(_ id: String) {
        if let index = artistDetailOrder.firstIndex(of: id) {
            artistDetailOrder.remove(at: index)
            artistDetailOrder.append(id)
        }
    }
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

    /// Clears the loaded flags after a server library scan completes so
    /// tabs refresh their data on subsequent visits.
    func invalidateForScan() {
        albumDetails = [:]
        playlistDetails = [:]
        artistDetails = [:]
        albumsLoaded = false
        recentAlbumsLoaded = false
        artistIndexesLoaded = false
        favoritesLoaded = false
        playlistsLoaded = false
        songsLoaded = false
        homeShelvesLoaded = false
    }

    /// Finds a cached artist by name across the alphabetical index and favorites.
    func findArtist(named name: String) -> Artist? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        for index in artistIndexes {
            if let match = index.artist?.first(where: {
                $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
            }) {
                return match
            }
        }
        return favoritesArtists.first(where: {
            $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        })
    }
}

extension AppState {
    /// Atomically updates the Home view shelves and cached favorites in a single MainActor
    /// commit, avoiding piecemeal Observable mutations that trigger layout shifts.
    @MainActor
    func updateHomeSnapshot(
        shelves: [AlbumListType: [SubsonicAlbum]],
        shelfErrors: [AlbumListType: String],
        favoritesArtists: [Artist]?,
        favoritesAlbums: [SubsonicAlbum]?,
        favoritesSongs: [SubsonicSong]? = nil
    ) {
        library.homeShelves = shelves
        library.homeShelfErrors = shelfErrors
        if let favoritesArtists {
            library.favoritesArtists = favoritesArtists
        }
        if let favoritesAlbums {
            library.favoritesAlbums = favoritesAlbums
        }
        if let favoritesSongs {
            library.favoritesSongs = favoritesSongs
        }
        library.homeShelvesLoaded = true
        if favoritesArtists != nil || favoritesAlbums != nil || favoritesSongs != nil {
            library.favoritesLoaded = true
        }
    }
}
