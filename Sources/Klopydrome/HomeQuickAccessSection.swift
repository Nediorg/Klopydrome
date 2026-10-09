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
    var loading: Bool = false

    var body: some View {
        let items = quickAccessItems
        if loading && items.isEmpty {
            skeletonSection
        } else if !items.isEmpty {
            contentSection(items)
        }
    }

    private var skeletonSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Быстрый доступ".localized)
                .font(.title3.bold())

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                spacing: 8
            ) {
                ForEach(0..<8, id: \.self) { _ in
                    PillCardPlaceholder()
                }
            }
        }
    }

    private func contentSection(_ items: [HomeQuickAccessItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Быстрый доступ".localized)
                .font(.title3.bold())

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                spacing: 8
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

    /// Selects up to 8 entities using a deterministic 2-row layout:
    /// - Row 1 (up to 4 items): Recents (recent playlists + recently played albums).
    /// - Row 2 (up to 4 items): Favorites & Pinned (followed playlists + starred artists + starred albums).
    /// Backfilled with frequent and newest albums if rows are incomplete.
    private var quickAccessItems: [HomeQuickAccessItem] {
        let recents = resolveRecentItems()
        let favorites = resolveFavoriteItems()
        let frequent = resolveFrequentItems()
        let newest = resolveNewestItems()

        var row1: [HomeQuickAccessItem] = []
        var row2: [HomeQuickAccessItem] = []
        var seenIDs = Set<String>()

        func tryAdd(to row: inout [HomeQuickAccessItem], item: HomeQuickAccessItem, limit: Int = 4) -> Bool {
            guard row.count < limit, !seenIDs.contains(item.id) else { return false }
            seenIDs.insert(item.id)
            row.append(item)
            return true
        }

        // 1. Fill Row 1 with recents
        for item in recents {
            _ = tryAdd(to: &row1, item: item)
        }

        // 2. Fill Row 2 with favorites
        for item in favorites {
            _ = tryAdd(to: &row2, item: item)
        }

        // 3. Backfill pool from frequent and newest
        let backfillPool = frequent + newest

        for item in backfillPool where row1.count < 4 {
            _ = tryAdd(to: &row1, item: item)
        }

        for item in backfillPool where row2.count < 4 {
            _ = tryAdd(to: &row2, item: item)
        }

        // 4. If any row is still under 4, spillover from other collections
        if row1.count < 4 {
            for item in favorites where row1.count < 4 {
                _ = tryAdd(to: &row1, item: item)
            }
        }
        if row2.count < 4 {
            for item in recents where row2.count < 4 {
                _ = tryAdd(to: &row2, item: item)
            }
        }

        return row1 + row2
    }

    /// Resolves recently visited playlists and server recently played albums.
    private func resolveRecentItems() -> [HomeQuickAccessItem] {
        var items: [HomeQuickAccessItem] = []
        let allPlaylists = app.library.playlists
        let recentPlayedAlbums = app.library.homeShelves[.recent] ?? []

        // Recent playlists (up to 2 if recent albums are available)
        let maxPlaylists = recentPlayedAlbums.isEmpty ? 4 : 2
        var playlistCount = 0
        for id in app.recentPlaylistIDs {
            if let playlist = allPlaylists.first(where: { $0.id == id }) {
                items.append(.playlist(playlist))
                playlistCount += 1
                if playlistCount >= maxPlaylists { break }
            }
        }

        // Server recently played albums (AlbumListType.recent)
        for album in recentPlayedAlbums {
            items.append(.album(album))
        }

        return items
    }

    /// Resolves favorite/starred entities across the library.
    private func resolveFavoriteItems() -> [HomeQuickAccessItem] {
        var items: [HomeQuickAccessItem] = []

        // Followed playlists (up to 2 if favorite artists/albums are available)
        let hasOtherFavorites = !app.library.favoritesArtists.isEmpty ||
            !app.library.favoritesAlbums.isEmpty ||
            !(app.library.homeShelves[.starred] ?? []).isEmpty
        let maxFollowed = hasOtherFavorites ? 2 : 4
        var followedCount = 0
        for id in app.followedPlaylistIDs {
            if let playlist = app.library.playlists.first(where: { $0.id == id }) {
                items.append(.playlist(playlist))
                followedCount += 1
                if followedCount >= maxFollowed { break }
            }
        }

        // Favorite artists
        for artist in app.library.favoritesArtists {
            items.append(.artist(artist))
        }

        // Favorite albums (from favoritesAlbums or homeShelves[.starred])
        let starredAlbums = !app.library.favoritesAlbums.isEmpty
            ? app.library.favoritesAlbums
            : (app.library.homeShelves[.starred] ?? [])
        for album in starredAlbums {
            items.append(.album(album))
        }

        return items
    }

    /// Resolves frequent server albums as a fallback.
    private func resolveFrequentItems() -> [HomeQuickAccessItem] {
        let frequent = app.library.homeShelves[.frequent] ?? []
        return frequent.map { .album($0) }
    }

    /// Resolves recently added server albums as a fallback.
    private func resolveNewestItems() -> [HomeQuickAccessItem] {
        let newest = app.library.homeShelves[.newest] ?? app.library.recentAlbums
        return newest.map { .album($0) }
    }
}

/// Shimmering placeholder card for Quick Access while library data loads.
struct PillCardPlaceholder: View {
    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.primary.opacity(0.08))
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 90, height: 11)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                    .frame(width: 55, height: 9)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .shimmering()
        .accessibilityHidden(true)
    }
}
