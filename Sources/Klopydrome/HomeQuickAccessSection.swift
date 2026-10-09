import SwiftUI
import NavidromeClient

/// An item displayed in the Quick Access ("Быстрый доступ") grid on the Home screen.
enum HomeQuickAccessItem: Identifiable, Equatable {
    case playlist(PlaylistSummary)
    case artist(Artist)
    case album(SubsonicAlbum)

    var id: String {
        switch self {
        case .playlist(let playlist): return "p-\(playlist.id)"
        case .artist(let artist): return "a-\(artist.id)"
        case .album(let album): return "al-\(album.id)"
        }
    }

    static func == (lhs: HomeQuickAccessItem, rhs: HomeQuickAccessItem) -> Bool {
        lhs.id == rhs.id
    }
}

/// Compact Quick Access section placed at the top of the Home view.
/// Prioritizes the user's recent activity while ensuring favorites are always accessible.
struct HomeQuickAccessSection: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let items = quickAccessItems
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("Быстрый доступ".localized)
                    .font(.title2.bold())

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220, maximum: 360), spacing: 12)],
                    spacing: 10
                ) {
                    ForEach(items) { item in
                        switch item {
                        case .playlist(let playlist):
                            PlaylistPillCard(playlist: playlist) {
                                app.openPlaylist(playlist)
                            }
                        case .artist(let artist):
                            ArtistPillCard(artist: artist) {
                                app.openArtistInLibrary(artist)
                            }
                        case .album(let album):
                            AlbumPillCard(album: album) {
                                app.openAlbumInLibrary(album)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Selects up to 6 entities by blending recents and favorites.
    private var quickAccessItems: [HomeQuickAccessItem] {
        let recents = resolveRecentItems()
        let favorites = resolveFavoriteItems()
        let frequent = resolveFrequentItems()

        var result: [HomeQuickAccessItem] = []
        var seenIDs = Set<String>()

        func appendIfNew(_ item: HomeQuickAccessItem) {
            guard result.count < 6, !seenIDs.contains(item.id) else { return }
            seenIDs.insert(item.id)
            result.append(item)
        }

        // Primary pass: weave recents and favorites for a balanced top shelf
        var recentIndex = 0
        var favoriteIndex = 0

        while result.count < 6 && (recentIndex < recents.count || favoriteIndex < favorites.count) {
            if recentIndex < recents.count {
                appendIfNew(recents[recentIndex])
                recentIndex += 1
            }
            if favoriteIndex < favorites.count {
                appendIfNew(favorites[favoriteIndex])
                favoriteIndex += 1
            }
        }

        // Backfill pass from frequent server albums if still under 6 items
        for item in frequent where result.count < 6 {
            appendIfNew(item)
        }

        return result
    }

    /// Resolves recently visited, played, or modified items.
    private func resolveRecentItems() -> [HomeQuickAccessItem] {
        var items: [HomeQuickAccessItem] = []
        let allPlaylists = app.library.playlists
        let recentShelves = app.library.homeShelves[.recent] ?? app.library.recentAlbums

        // 1. Recent playlists
        for id in app.recentPlaylistIDs {
            if let playlist = allPlaylists.first(where: { $0.id == id }) {
                items.append(.playlist(playlist))
            }
        }

        // 2. Server recently played albums (AlbumListType.recent)
        for album in recentShelves.prefix(4) {
            items.append(.album(album))
        }

        return items
    }

    /// Resolves favorite/starred entities across the library.
    private func resolveFavoriteItems() -> [HomeQuickAccessItem] {
        var items: [HomeQuickAccessItem] = []

        // 1. Followed playlists
        for id in app.followedPlaylistIDs {
            if let playlist = app.library.playlists.first(where: { $0.id == id }) {
                items.append(.playlist(playlist))
            }
        }

        // 2. Favorite artists
        for artist in app.library.favoritesArtists {
            items.append(.artist(artist))
        }

        // 3. Favorite albums
        for album in app.library.favoritesAlbums {
            items.append(.album(album))
        }

        return items
    }

    /// Resolves frequent server albums as a fallback.
    private func resolveFrequentItems() -> [HomeQuickAccessItem] {
        let frequent = app.library.homeShelves[.frequent] ?? []
        return frequent.map { .album($0) }
    }
}
