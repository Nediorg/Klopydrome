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

    @ObservationIgnored private var playlistDetailOrder: [String] = []
    var playlistDetails: [String: PlaylistDetail] = [:] {
        didSet {
            for key in pruneOrder(Set(playlistDetails.keys), order: &playlistDetailOrder) {
                playlistDetails.removeValue(forKey: key)
            }
        }
    }

    func recordPlaylistDetailAccess(_ id: String) {
        touchLRU(&playlistDetailOrder, key: id)
    }

    @ObservationIgnored private var albumDetailOrder: [String] = []
    var albumDetails: [String: AlbumDetail] = [:] {
        didSet {
            for key in pruneOrder(Set(albumDetails.keys), order: &albumDetailOrder) {
                albumDetails.removeValue(forKey: key)
            }
        }
    }

    func recordAlbumDetailAccess(_ id: String) {
        touchLRU(&albumDetailOrder, key: id)
    }

    @ObservationIgnored private var artistDetailOrder: [String] = []
    var artistDetails: [String: ArtistDetail] = [:] {
        didSet {
            for key in pruneOrder(Set(artistDetails.keys), order: &artistDetailOrder) {
                artistDetails.removeValue(forKey: key)
            }
        }
    }

    func recordArtistDetailAccess(_ id: String) {
        touchLRU(&artistDetailOrder, key: id)
    }

    private func pruneOrder(_ currentKeys: Set<String>, order: inout [String]) -> [String] {
        order.removeAll { !currentKeys.contains($0) }
        for key in currentKeys where !order.contains(key) {
            order.append(key)
        }
        var evicted: [String] = []
        while order.count > Self.maxDetailCacheCapacity {
            evicted.append(order.removeFirst())
        }
        return evicted
    }

    private func touchLRU(_ order: inout [String], key: String) {
        if let index = order.firstIndex(of: key) {
            order.remove(at: index)
            order.append(key)
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
