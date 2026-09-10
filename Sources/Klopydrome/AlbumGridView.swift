import SwiftUI
import NavidromeClient

/// The per-tab settings that make the two album grids differ. Everything else —
/// pagination, search/debounce, filter+sort, empty states — is shared.
/// MainActor-isolated because the backing `LibraryCache` store is `@MainActor`.
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
        title: "Альбомы",
        listType: .alphabeticalByName,
        defaultSort: .name,
        emptySystemImage: "square.stack",
        emptyMessage: "Альбомы появятся здесь, когда будут в вашей библиотеке.",
        albums: \LibraryCache.albums,
        loaded: \LibraryCache.albumsLoaded,
        allLoaded: \LibraryCache.albumsAllLoaded
    )

    static let recentlyAdded = AlbumGridConfig(
        title: "Недавно добавленные",
        listType: .newest,
        defaultSort: .recentlyAdded,
        emptySystemImage: "clock",
        emptyMessage: "Альбомы, добавленные в библиотеку, появятся здесь.",
        albums: \LibraryCache.recentAlbums,
        loaded: \LibraryCache.recentAlbumsLoaded,
        allLoaded: \LibraryCache.recentAllLoaded
    )
}

/// Paged album grid with search, favorites filter and sorting. Powers both the
/// "Альбомы" and "Недавно добавленные" tabs; the two differ only in
/// `AlbumGridConfig`.
struct AlbumGridView: View {
    @Environment(AppState.self) private var app
    private let config: AlbumGridConfig

    /// A compact initial response reaches the first useful grid sooner. Further
    /// pages retain the larger batch size once the user has content to browse.
    private let initialPageSize = 48
    private let pageSize = 100
    @State private var loading = true
    @State private var isLoadingMore = false
    /// Set when the initial fetch fails, so an error renders with retry
    /// instead of a misleading "Нет альбомов".
    @State private var loadError: String?
    /// A later pagination failure must not be treated as the end of the list.
    @State private var pageLoadError: String?

    @State private var sort: LibrarySort
    @State private var favoritesOnly = false
    @State private var searchText = ""
    @State private var processedAlbums: [SubsonicAlbum] = []

    private var currentType: AlbumListType? { sort.asAlbumListType }
    private var isLocalSort: Bool { currentType == nil }
    /// Debounced reprocess task for the search field.
    @State private var searchTask: Task<Void, Never>?
    /// Off-main reprocess task (filter + sort of the whole album list).
    @State private var reprocessTask: Task<Void, Never>?
    /// Increments each reprocess; results apply only when their token still
    /// matches, so a slow background sort can't overwrite a newer one.
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
                Picker("Показать", selection: $favoritesOnly) {
                    Text("Все альбомы".localized).tag(false)
                    Text("Только избранное".localized).tag(true)
                }
                .pickerStyle(.inline)

                Divider()

                Picker("Сортировка", selection: $sort) {
                    ForEach(LibrarySort.allCases) { option in
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
                    LibraryUnavailableView(title: "Не удалось загрузить",
                                           systemImage: "wifi.exclamationmark",
                                           message: loadError,
                                           retry: { Task { await refresh() } })
                        .emptyStatePinnedToTop()
                } else if loading && albums.isEmpty {
                    initialLoadingGrid
                } else if albums.isEmpty {
                    LibraryUnavailableView(title: "Нет альбомов",
                                           systemImage: config.emptySystemImage,
                                           message: config.emptyMessage)
                        .emptyStatePinnedToTop()
                } else if processedAlbums.isEmpty {
                    ContentUnavailableView("Ничего не найдено",
                                           systemImage: "magnifyingglass",
                                           // swiftlint:disable:next line_length
                                            description: Text("Попробуйте изменить запрос или параметры фильтра.".localized))
                        .emptyStatePinnedToTop()
                } else {
                    GeometryReader { geo in
                        let available = geo.size.width - 48
                        let count = max(1, Int((available + gap) / (minCard + gap)))
                        let rawWidth = (available - CGFloat(count - 1) * gap) / CGFloat(count)
                        let cardWidth = floor(rawWidth)
                        let cols = Array(repeating: GridItem(.fixed(cardWidth), spacing: gap), count: count)
                        ScrollView {
                            LazyVGrid(columns: cols, spacing: gap) {
                                ForEach(processedAlbums) { album in
                                    NavigationLink(value: album) {
                                        AlbumCard(album: album, width: cardWidth, reservesTitleLines: true)
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
        .refreshable { await refresh() }
        .task { await loadIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .foregroundRefreshRequested)) { _ in
            // A background failure leaves `loadError`/*page* error latched with
            // only manual retry; one automatic retry per activation resumes it.
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

    @ViewBuilder
    private var paginationFooter: some View {
        if let pageLoadError {
            VStack(spacing: 8) {
                Divider().opacity(0.4)
                Button { Task { await loadMore() } } label: {
                    Label("Повторить загрузку".localized, systemImage: "arrow.clockwise")
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
                .accessibilityLabel("Повторить загрузку".localized)
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

    /// The first network response has not arrived yet, but the grid dimensions
    /// are already useful feedback and avoid a visually empty tab.
    private var initialLoadingGrid: some View {
        GeometryReader { geo in
            let available = geo.size.width - 48
            let count = max(1, Int((available + gap) / (minCard + gap)))
            let rawWidth = (available - CGFloat(count - 1) * gap) / CGFloat(count)
            let cardWidth = floor(rawWidth)
            let cols = Array(repeating: GridItem(.fixed(cardWidth), spacing: gap), count: count)
            ScrollView {
                LazyVGrid(columns: cols, spacing: gap) {
                    ForEach(0..<12, id: \.self) { _ in
                        AlbumCardPlaceholder(width: cardWidth)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
            .scrollClipDisabled()
        }
        .accessibilityLabel("Загрузка альбомов")
    }

    /// Fetches the first page only when the store has never been loaded, so a
    /// revisit to the tab is instant and keeps scroll position. Pull-to-refresh
    /// still forces a full reload via `refresh()`.
    private func loadIfNeeded() async {
        guard !app.library[keyPath: config.loaded] else {
            // Already-loaded store: the tab re-appears with fresh `@State`, so
            // `processedAlbums` is empty and the spinner is running. Recompute
            // the grid from the cache and stop the spinner — otherwise every
            // revisit shows "Ничего не найдено" (or a stuck spinner when the
            // library is genuinely empty) even though albums exist.
            loading = false
            reprocess()
            return
        }
        await refresh()
    }

    /// Debounces search-field reprocessing so fast typing doesn't filter + sort
    /// the whole album list on every character.
    private func scheduleReprocess() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            reprocess()
        }
    }

    /// Filters (and locally sorts when needed) into `processedAlbums`.
    /// Server sorts are already ordered via `currentType`; local sorts
    /// (duration/genre/id/release) are applied here.
    private func reprocess() {
        let generation = reprocessGeneration + 1
        reprocessGeneration = generation

        // Snapshot all inputs synchronously on the main actor.
        let base = albums
        let onlyFav = favoritesOnly
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        let sortKind = sort
        let local = isLocalSort
        var starredIDs: Set<String>?
        if onlyFav { starredIDs = Set(base.filter { app.isStarred($0) }.map(\.id)) }

        reprocessTask?.cancel()
        reprocessTask = Task.detached(priority: .userInitiated) { [self] in
            let result = Self.compute(base, favoritesOnly: onlyFav, starredIDs: starredIDs,
                                      query: query, sort: sortKind)
            await MainActor.run {
                guard !Task.isCancelled, self.reprocessGeneration == generation else { return }
                self.processedAlbums = result
            }
        }
    }

    nonisolated private static func compute(_ source: [SubsonicAlbum], favoritesOnly: Bool,
                                            starredIDs: Set<String>?, query: String,
                                            sort: LibrarySort) -> [SubsonicAlbum] {
        var list = source
        if favoritesOnly, let starred = starredIDs {
            list = list.filter { starred.contains($0.id) }
        }
        if !query.isEmpty {
            list = list.filter {
                ($0.displayName + " " + ($0.artist ?? "")).lowercased().contains(query)
            }
        }
        if sort.asAlbumListType == nil {
            let descending: Bool = {
                switch sort {
                case .name, .artist, .genre, .id: return false
                default: return true
                }
            }()
            return sortedAlbums(list, by: sort.asArtistAlbumSort, descending: descending)
        }
        return list
    }

    private func handleSortChange() async {
        reprocessTask?.cancel()
        searchTask?.cancel()
        isLoadingMore = false
        pageLoadError = nil
        loadError = nil
        loading = true
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
