import SwiftUI
import NavidromeClient

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
            Text("Quick Access".localized)
                .font(.title3.bold())

            skeletonGrid(forMask: false)
                .shimmering()
                .mask {
                    skeletonGrid(forMask: true)
                }
        }
    }

    private func skeletonGrid(forMask: Bool) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
            spacing: 8
        ) {
            ForEach(0..<8, id: \.self) { _ in
                SkeletonPillCard(forMask: forMask)
            }
        }
    }

    private func contentSection(_ items: [HomeQuickAccessItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Access".localized)
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

        for item in recents {
            _ = tryAdd(to: &row1, item: item)
        }

        for item in favorites {
            _ = tryAdd(to: &row2, item: item)
        }

        let backfillPool = frequent + newest

        for item in backfillPool where row1.count < 4 {
            _ = tryAdd(to: &row1, item: item)
        }

        for item in backfillPool where row2.count < 4 {
            _ = tryAdd(to: &row2, item: item)
        }

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

    private func resolveRecentItems() -> [HomeQuickAccessItem] {
        var items: [HomeQuickAccessItem] = []
        let allPlaylists = app.library.playlists
        let recentPlayedAlbums = app.library.homeShelves[.recent] ?? []

        let maxPlaylists = recentPlayedAlbums.isEmpty ? 4 : 2
        var playlistCount = 0
        for id in app.recentPlaylistIDs {
            if let playlist = allPlaylists.first(where: { $0.id == id }) {
                items.append(.playlist(playlist))
                playlistCount += 1
                if playlistCount >= maxPlaylists { break }
            }
        }

        for album in recentPlayedAlbums {
            items.append(.album(album))
        }

        return items
    }

    private func resolveFavoriteItems() -> [HomeQuickAccessItem] {
        var items: [HomeQuickAccessItem] = []

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

        for artist in app.library.favoritesArtists {
            items.append(.artist(artist))
        }

        let starredAlbums = !app.library.favoritesAlbums.isEmpty
            ? app.library.favoritesAlbums
            : (app.library.homeShelves[.starred] ?? [])
        for album in starredAlbums {
            items.append(.album(album))
        }

        return items
    }

    private func resolveFrequentItems() -> [HomeQuickAccessItem] {
        let frequent = app.library.homeShelves[.frequent] ?? []
        return frequent.map { .album($0) }
    }

    private func resolveNewestItems() -> [HomeQuickAccessItem] {
        let newest = app.library.homeShelves[.newest] ?? app.library.recentAlbums
        return newest.map { .album($0) }
    }
}
