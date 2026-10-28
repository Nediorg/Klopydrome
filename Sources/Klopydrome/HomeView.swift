import SwiftUI
import NavidromeClient

struct HomeView: View {
    @Environment(AppState.self) private var app

    enum Shelf: String, CaseIterable, Identifiable {
        case recent = "Recently Played"
        case new = "Recently Added"
        case frequent = "Most Played"
        case starred = "Favorite Albums"
        case random = "For You"

        var listType: AlbumListType {
            switch self {
            case .recent: return .recent
            case .new: return .newest
            case .frequent: return .frequent
            case .starred: return .starred
            case .random: return .random
            }
        }
        var id: String { rawValue }

        var localizedTitle: String {
            rawValue.localized
        }
    }

    private enum HomeFetchResult {
        case shelf(Shelf, [SubsonicAlbum], String?)
        case starred(artists: [Artist], albums: [SubsonicAlbum], songs: [SubsonicSong])
    }

    @State private var loading = true
    @State private var loadingShelves: Set<Shelf> = []

    private var errorsByShelf: [Shelf: String] {
        var dict: [Shelf: String] = [:]
        for shelf in Shelf.allCases {
            if let err = app.library.homeShelfErrors[shelf.listType] {
                dict[shelf] = err
            }
        }
        return dict
    }

    private var albumsByShelf: [Shelf: [SubsonicAlbum]] {
        var dict: [Shelf: [SubsonicAlbum]] = [:]
        for shelf in Shelf.allCases {
            dict[shelf] = app.library.homeShelves[shelf.listType] ?? []
        }
        return dict
    }

    var body: some View {
        if app.isOfflineSession {
            OfflineHomeView()
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 32) {
                    HomeQuickAccessSection(loading: loading && app.library.homeShelves.isEmpty)

                    ForEach(Shelf.allCases) { shelf in
                        let albums = albumsByShelf[shelf] ?? []
                        let hasError = errorsByShelf[shelf] != nil
                        let isLoading = loadingShelves.contains(shelf) || (loading && albums.isEmpty)
                        if !albums.isEmpty || isLoading || hasError {
                            albumShelf(shelf)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
            .scrollClipDisabled()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .refreshable { await load() }
            .task(id: app.client != nil) { await loadIfNeeded() }
        }
    }

    private func shelfHeader(_ shelf: Shelf) -> some View {
        HStack(spacing: 6) {
            Text(shelf.localizedTitle)
                .font(.title2.bold())
            Spacer()
            if loadingShelves.contains(shelf) {
                ProgressView()
                    .controlSize(.small)
            }
            Button {
                Task { await reloadShelf(shelf) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(minWidth: 30, minHeight: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(AMColor.accent)
            .hoverBrighten()
            .accessibilityLabel("Refresh".localized)
            .help("Refresh".localized)
        }
    }

    private func albumShelf(_ shelf: Shelf) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            shelfHeader(shelf)

            let albums = albumsByShelf[shelf] ?? []
            if albums.isEmpty && (loading || loadingShelves.contains(shelf)) {
                SkeletonCardShelf(count: 6, cardSize: 165, spacing: 18)
            } else if let error = errorsByShelf[shelf] {
                retryRow(shelf, error: error)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 18) {
                        ForEach(albums) { album in
                            Button {
                                app.openAlbumInLibrary(album)
                            } label: {
                                AlbumCard(album: album)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                }
                .scrollClipDisabled()
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func retryRow(_ shelf: Shelf, error: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Failed to load".localized)
                .font(.callout.weight(.semibold))
            Text(error)
                .font(.caption)
                .foregroundStyle(AMColor.secondaryText)
                .lineLimit(2)
            Button("Retry".localized) {
                Task { await reloadShelf(shelf) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(width: 220, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(AMColor.surface))
    }

    private func loadIfNeeded() async {
        let hasAnyData = Shelf.allCases.contains { shelf in
            !(app.library.homeShelves[shelf.listType] ?? []).isEmpty
        }
        guard !app.library.homeShelvesLoaded || !hasAnyData else {
            loading = false
            loadingShelves.removeAll()
            return
        }
        await load()
    }

    private func fetchShelf(_ shelf: Shelf, client: SubsonicClient) async -> HomeFetchResult? {
        do {
            let albums = try await client.getAlbumList2(type: shelf.listType, size: 24)
            return .shelf(shelf, albums, nil)
        } catch {
            if error is CancellationError { return nil }
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
                return nil
            }
            return .shelf(shelf, [], error.localizedDescription)
        }
    }

    private func fetchStarred(client: SubsonicClient) async -> HomeFetchResult? {
        guard let starred = try? await client.getStarred2() else { return nil }
        return .starred(artists: starred.artists, albums: starred.albums, songs: starred.songs)
    }

    private func load() async {
        guard let client = app.client else {
            loading = false
            return
        }
        if app.library.homeShelves.isEmpty { loading = true }
        loadingShelves = Set(Shelf.allCases)
        defer {
            loading = false
            loadingShelves.removeAll()
        }
        await withTaskGroup(of: HomeFetchResult?.self) { group in
            for shelf in Shelf.allCases {
                group.addTask { await fetchShelf(shelf, client: client) }
            }
            group.addTask { await fetchStarred(client: client) }

            var shelves: [AlbumListType: [SubsonicAlbum]] = [:]
            var errors: [AlbumListType: String] = [:]
            var artists: [Artist]?
            var albums: [SubsonicAlbum]?
            var songs: [SubsonicSong]?

            for await result in group {
                guard let result else { continue }
                switch result {
                case .shelf(let shelf, let albums, let error):
                    shelves[shelf.listType] = albums
                    if let error { errors[shelf.listType] = error }
                case .starred(let starredArtists, let starredAlbums, let starredSongs):
                    artists = starredArtists
                    albums = starredAlbums
                    songs = starredSongs
                }
            }

            guard !Task.isCancelled else { return }
            await applyHomeSnapshot(shelves: shelves, errors: errors, artists: artists, albums: albums, songs: songs)
        }
    }

    private func applyHomeSnapshot(
        shelves: [AlbumListType: [SubsonicAlbum]],
        errors: [AlbumListType: String],
        artists: [Artist]?,
        albums: [SubsonicAlbum]?,
        songs: [SubsonicSong]?
    ) async {
        app.updateHomeSnapshot(
            shelves: shelves,
            shelfErrors: errors,
            favoritesArtists: artists,
            favoritesAlbums: albums,
            favoritesSongs: songs
        )
        if shelves.values.contains(where: { !$0.isEmpty }) {
            await app.persistHomeShelvesToDisk()
        }
        if artists != nil || albums != nil || songs != nil {
            await app.persistFavoritesToDisk()
        }
    }

    private func reloadShelf(_ shelf: Shelf) async {
        guard let client = app.client else { return }
        loadingShelves.insert(shelf)
        defer { loadingShelves.remove(shelf) }
        do {
            app.library.homeShelves[shelf.listType] = try await client.getAlbumList2(type: shelf.listType, size: 24)
            app.library.homeShelfErrors[shelf.listType] = nil
            await app.persistHomeShelvesToDisk()
        } catch {
            if error is CancellationError { return }
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return }
            app.library.homeShelfErrors[shelf.listType] = error.localizedDescription
        }
    }
}

struct AlbumCard: View {
    let album: SubsonicAlbum
    var width: CGFloat = 165
    var showsArtist: Bool = true
    var showsYear: Bool = false
    var reservesTitleLines: Bool = true

    @Environment(AppState.self) private var app
    @State private var hovering = false

    private var isStarred: Bool { app.isStarred(album) }

    var body: some View {
        MediaCard(
            width: width,
            title: album.displayName,
            subtitle: showsArtist ? album.artist : nil,
            line2: (showsYear && album.year != nil) ? String(album.year!) : nil,
            reservesTitleLines: reservesTitleLines
        ) {
            CoverArtView(coverArt: album.coverArt, size: width, cornerRadius: 6, shadow: true)
        } trailingBadge: {
            if hovering || isStarred {
                Button {
                    app.toggleStar(album)
                } label: {
                    Image(systemName: isStarred ? "star.fill" : "star")
                        .font(.system(size: 13))
                        .foregroundStyle(isStarred ? AMColor.accent : .white)
                        .padding(5)
                        .background(Circle().fill(.black.opacity(0.35)))
                }
                .buttonStyle(.plain)
                .padding(6)
                .help(isStarred ? "Remove from Favorites".localized : "Add to Favorites".localized)
                .accessibilityLabel(
                    isStarred ? "Remove album from Favorites".localized : "Add Album to Favorites".localized
                )
                .transition(.opacity)
            }
        }
        .onHover { hovering = $0 }
        .accessibilityLabel(album.displayName)
        .accessibilityAction(named: isStarred ? "Remove from Favorites".localized : "Add to Favorites".localized) {
            app.toggleStar(album)
        }
        .contextMenu {
            AlbumContextMenuItems(album: album)
        }
    }
}

extension AlbumCard: Equatable {
    static func == (lhs: AlbumCard, rhs: AlbumCard) -> Bool {
        lhs.album.id == rhs.album.id
            && lhs.album.title == rhs.album.title
            && lhs.album.name == rhs.album.name
            && lhs.album.artist == rhs.album.artist
            && lhs.album.year == rhs.album.year
            && lhs.album.coverArt == rhs.album.coverArt
            && lhs.album.starred == rhs.album.starred
            && lhs.width == rhs.width
            && lhs.showsArtist == rhs.showsArtist
            && lhs.showsYear == rhs.showsYear
            && lhs.reservesTitleLines == rhs.reservesTitleLines
    }
}