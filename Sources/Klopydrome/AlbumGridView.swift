import SwiftUI
import NavidromeClient

@MainActor
struct AlbumGridConfig {
    let title: String
    let listType: AlbumListType
    let defaultSort: LibrarySort
    let emptySystemImage: String
    let emptyMessage: String
    let albums: WritableKeyPath<LibraryCache, [SubsonicAlbum]>
    let loaded: WritableKeyPath<LibraryCache, Bool>
    let allLoaded: WritableKeyPath<LibraryCache, Bool>

    static let albums = AlbumGridConfig(
        title: "Albums",
        listType: .alphabeticalByName,
        defaultSort: .name,
        emptySystemImage: "square.stack",
        emptyMessage: "Albums will appear here when they're in your library.",
        albums: \LibraryCache.albums,
        loaded: \LibraryCache.albumsLoaded,
        allLoaded: \LibraryCache.albumsAllLoaded
    )

    static let recentlyAdded = AlbumGridConfig(
        title: "Recently Added",
        listType: .newest,
        defaultSort: .recentlyAdded,
        emptySystemImage: "clock",
        emptyMessage: "Albums added to your library will appear here.",
        albums: \LibraryCache.recentAlbums,
        loaded: \LibraryCache.recentAlbumsLoaded,
        allLoaded: \LibraryCache.recentAllLoaded
    )
}

struct AlbumGridView: View {
    @Environment(AppState.self) private var app
    private let config: AlbumGridConfig

    private let initialPageSize = 48
    private let pageSize = 100
    @State private var loading = true
    @State private var isLoadingMore = false
    @State private var loadError: String?
    @State private var pageLoadError: String?

    @State private var sort: LibrarySort
    @State private var favoritesOnly = false
    @State private var searchText = ""
    @State private var processedAlbums: [SubsonicAlbum] = []
    @State private var reprocessing = false

    private var displayAlbums: [SubsonicAlbum] {
        if !processedAlbums.isEmpty {
            return processedAlbums
        }
        if searchText.isEmpty && !favoritesOnly {
            return albums
        }
        return []
    }

    private var currentType: AlbumListType? { sort.asAlbumListType }
    private var isLocalSort: Bool { currentType == nil }
    @State private var searchTask: Task<Void, Never>?
    @State private var reprocessTask: Task<Void, Never>?
    @State private var reprocessGeneration = 0

    private let gap: CGFloat = 16
    private let minCard: CGFloat = 165

    init(config: AlbumGridConfig) {
        self.config = config
        _sort = State(initialValue: config.defaultSort)
    }

    var body: some View {
        VStack(spacing: 0) {
            LibraryHeader(title: config.title, searchText: $searchText) {
                Picker("Show".localized, selection: $favoritesOnly) {
                    Text("All Albums".localized).tag(false)
                    Text("Favorites only".localized).tag(true)
                }
                .pickerStyle(.inline)

                Divider()

                Picker("Sort".localized, selection: $sort) {
                    ForEach(AlbumSort.allCases) { option in
                        Text(option.label.localized).tag(option)
                    }
                }
                .pickerStyle(.inline)

            }
            .background(.ultraThinMaterial)
            .overlay(alignment: .bottom) { Divider().opacity(0.35) }
            .zIndex(1)

            Group {
                if let loadError {
                    LibraryUnavailableView(title: "Failed to load".localized,
                                           systemImage: "wifi.exclamationmark",
                                           message: loadError,
                                           retry: { Task { await refresh() } })
                        .emptyStatePinnedToTop()
                } else if loading && albums.isEmpty {
                    initialLoadingGrid
                } else if albums.isEmpty {
                    LibraryUnavailableView(title: "No Albums".localized,
                                           systemImage: config.emptySystemImage,
                                           message: config.emptyMessage.localized)
                        .emptyStatePinnedToTop()
                } else if displayAlbums.isEmpty {
                    if reprocessing || (!app.library[keyPath: config.loaded] && loading) {
                        initialLoadingGrid
                    } else {
                        ContentUnavailableView(
                            "Nothing Found".localized,
                            systemImage: "magnifyingglass",
                            description: Text("Try changing the query or filter settings.".localized)
                        )
                            .emptyStatePinnedToTop()
                    }
                } else {
                    GeometryReader { geo in
                        let available = geo.size.width - 48
                        let count = max(1, Int((available + gap) / (minCard + gap)))
                        let rawWidth = (available - CGFloat(count - 1) * gap) / CGFloat(count)
                        let cardWidth = floor(rawWidth)
                        let cols = Array(repeating: GridItem(.fixed(cardWidth), spacing: gap), count: count)
                        ScrollView {
                            LazyVGrid(columns: cols, spacing: gap) {
                                ForEach(displayAlbums) { album in
                                    Button {
                                        app.openAlbumInLibrary(album)
                                    } label: {
                                        AlbumCard(album: album, width: cardWidth, reservesTitleLines: true)
                                            .equatable()
                                    }
                                    .buttonStyle(.plain)
                                }
                                if !allLoaded {
                                    Color.clear.frame(height: 200)
                                        .gridCellColumns(count)
                                        .onAppear { Task { await loadMore() } }
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 20)
                            if !allLoaded { paginationFooter }
                        }
                        .scrollClipDisabled()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .refreshable { await refresh() }
        .task { await loadIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .foregroundRefreshRequested)) { _ in
            if loadError != nil {
                Task { await refresh() }
            } else if pageLoadError != nil {
                Task { await loadMore() }
            }
        }
        .onChange(of: searchText) { scheduleReprocess() }
        .onChange(of: favoritesOnly) { reprocess() }
        .onChange(of: sort) { Task { await handleSortChange() } }
    }

    private var albums: [SubsonicAlbum] { app.library[keyPath: config.albums] }
    private var allLoaded: Bool { app.library[keyPath: config.allLoaded] }

    private func loadIfNeeded() async {
        guard !app.library[keyPath: config.loaded] else {
            loading = false
            reprocess()
            return
        }
        await refresh()
    }

    private func scheduleReprocess() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            reprocess()
        }
    }

    private func reprocess() {
        let generation = reprocessGeneration + 1
        reprocessGeneration = generation

        let base = albums
        if base.isEmpty {
            processedAlbums = []
            reprocessing = false
            return
        }
        reprocessing = true
        let onlyFav = favoritesOnly
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        let sortKind = sort
        var starredIDs: Set<String>?
        if onlyFav { starredIDs = Set(base.filter { app.isStarred($0) }.map(\.id)) }

        reprocessTask?.cancel()
        reprocessTask = Task.detached(priority: .userInitiated) {
            guard !Task.isCancelled else { return }
            let result = Self.compute(base, favoritesOnly: onlyFav, starredIDs: starredIDs,
                                      query: query, sort: sortKind)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard !Task.isCancelled, reprocessGeneration == generation else { return }
                processedAlbums = result
                reprocessing = false
            }
        }
    }

    private func handleSortChange() async {
        reprocessTask?.cancel()
        searchTask?.cancel()
        isLoadingMore = false
        pageLoadError = nil
        loadError = nil
        loading = true
        reprocessing = true
        reprocessGeneration += 1
        processedAlbums = []
        app.library[keyPath: config.albums] = []
        app.library[keyPath: config.allLoaded] = false
        app.library[keyPath: config.loaded] = false
        await refresh()
    }

    private func refresh() async {
        guard let client = app.client else { return }
        if albums.isEmpty { loading = true }
        defer { loading = false }
        do {
            let fresh = try await client.getAlbumList2(
                type: currentType ?? config.listType,
                size: initialPageSize,
                offset: 0
            )
            loadError = nil
            pageLoadError = nil
            app.library[keyPath: config.albums] = fresh
            app.library[keyPath: config.loaded] = true
            app.library[keyPath: config.allLoaded] = fresh.isEmpty || fresh.count < initialPageSize
            if config.listType == .newest {
                await app.persistRecentAlbumsToDisk()
            } else if config.listType == .alphabeticalByName {
                await app.persistAlbumsToDisk()
            }
        } catch {
            if albums.isEmpty { loadError = error.localizedDescription }
        }
        reprocess()
    }

    private func loadMore() async {
        guard !isLoadingMore, !allLoaded, let client = app.client else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        var lastError: String?
        for attempt in 0..<3 {
            do {
                let more = try await client.getAlbumList2(
                    type: currentType ?? config.listType,
                    size: pageSize,
                    offset: albums.count
                )
                pageLoadError = nil
                if more.isEmpty {
                    app.library[keyPath: config.allLoaded] = true
                } else {
                    app.library[keyPath: config.albums].append(contentsOf: more)
                    if more.count < pageSize { app.library[keyPath: config.allLoaded] = true }
                }
                reprocess()
                return
            } catch {
                lastError = error.localizedDescription
                if Task.isCancelled { return }
                if attempt < 2 {
                    let delay = UInt64(800_000_000 * (1 << attempt)) + UInt64.random(in: 0...200_000_000)
                    try? await Task.sleep(nanoseconds: delay)
                    if Task.isCancelled { return }
                }
            }
        }
        pageLoadError = lastError
    }
}

private extension AlbumGridView {
    @ViewBuilder
    var paginationFooter: some View {
        if let pageLoadError {
            VStack(spacing: 8) {
                Divider().opacity(0.4)
                Button { Task { await loadMore() } } label: {
                    Label("Retry".localized, systemImage: "arrow.clockwise")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                        .opacity(0.5)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(pageLoadError)
                .accessibilityLabel("Retry".localized)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 24)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 16)
                .onAppear { Task { await loadMore() } }
        }
    }

    var initialLoadingGrid: some View {
        SkeletonCardGrid(
            count: 12,
            minCard: minCard,
            gap: gap,
            accessibilityLabel: "Loading albums".localized
        )
    }

    nonisolated static func compute(
        _ source: [SubsonicAlbum],
        favoritesOnly: Bool,
        starredIDs: Set<String>?,
        query: String,
        sort: LibrarySort
    ) -> [SubsonicAlbum] {
        var list = source
        if favoritesOnly, let starred = starredIDs {
            list = list.filter { starred.contains($0.id) }
        }
        guard !Task.isCancelled else { return [] }
        if !query.isEmpty {
            list = list.filter {
                ($0.displayName + " " + ($0.artist ?? "")).lowercased().contains(query)
            }
        }
        guard !Task.isCancelled else { return [] }
        if sort.asAlbumListType == nil {
            let descending: Bool = {
                switch sort {
                case .name, .artist, .genre, .id: return false
                default: return true
                }
            }()
            return sortedAlbums(list, by: sort, descending: descending)
        }
        return list
    }
}
