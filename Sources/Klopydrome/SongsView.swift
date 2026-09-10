import SwiftUI
import NavidromeClient

/// Library-wide song list. Navidrome has no "all songs" endpoint, so the whole
/// library is paged in via repeated `search3` calls with a `*` query, and each
/// fetched chunk is appended to the table as it arrives — no full-library wait
/// before the first rows render. Column sorting is always enabled.
/// Rendered as an Apple Music-style table under the shared `LibraryHeader`
/// (favorites filter + search), with sortable columns and column visibility
/// toggled via right-click on a column header.
struct SongsView: View {
    @Environment(AppState.self) private var app

    /// Songs fetched per `search3` page.
    private let chunkSize = 300

    private var songs: [SubsonicSong] { app.library.songs }
    /// True while the first page is still being fetched (nothing to show yet).
    @State private var loading = true
    /// True while additional pages are streaming in; the table stays visible.
    @State private var isLoadingMore = false
    /// Set when the initial load fails, so the tab renders the error with a
    /// retry instead of a misleading "Нет песен" (empty ≠ load failure).
    @State private var loadError: String?
    @State private var favoritesOnly = false
    @State private var searchText = ""
    @State private var sortOrder: [KeyPathComparator<SubsonicSong>] = [
        KeyPathComparator(\.title, order: .forward),
    ]
    /// Filtered + sorted result, recomputed only when its inputs change (not
    /// on every body evaluation) — avoids re-sorting the whole library on each
    /// render and giving `Table` a fresh array identity every frame.
    @State private var processedSongs: [SubsonicSong] = []
    /// Lowercased searchable text per song id, built once per song so typing
    /// doesn't re-join/lowercase the whole library on every keystroke.
    @State private var searchable: [String: String] = [:]
    /// Debounced reprocess task for the search field.
    @State private var searchTask: Task<Void, Never>?
    /// Off-main reprocess task (filter + sort of the whole library).
    @State private var reprocessTask: Task<Void, Never>?
    /// Increments every time a reprocess is launched; results only apply when
    /// their token still matches, so a slow background sort can't overwrite a
    /// newer one.
    @State private var reprocessGeneration = 0
    /// True while a reprocess already ran and new data landed meanwhile, so a
    /// further pass is still owed. Prevents flooding the pool with one
    /// full-library sort per loaded chunk.
    @State private var reprocessDirty = false
    /// True while a reprocess task is running, so per-chunk calls coalesce into
    /// the in-flight pass instead of stacking new ones.
    @State private var reprocessing = false
    /// Native `Table` column customization: shown when the user right-clicks a
    /// column header (Apple Music column picker). Initialized to the previous
    /// defaults.
    @State private var columnCustomization: TableColumnCustomization<SubsonicSong> = {
        var customization = TableColumnCustomization<SubsonicSong>()
        for column in SongColumn.allCases where column != .title {
            customization[visibility: column.id] = SongColumn.defaults.contains(column) ? .visible : .hidden
        }
        return customization
    }()

    var body: some View {
        VStack(spacing: 0) {
            LibraryHeader(title: "Песни", searchText: $searchText, isLoading: isLoadingMore) {
                Picker("Показать", selection: $favoritesOnly) {
                    Text("Все песни".localized).tag(false)
                    Text("Только избранное".localized).tag(true)
                }
                .pickerStyle(.inline)
            }

            Group {
                if let loadError, songs.isEmpty {
                    LibraryUnavailableView(title: "Не удалось загрузить",
                                           systemImage: "wifi.exclamationmark",
                                           message: loadError,
                                           retry: { Task { await load() } })
                        .emptyStatePinnedToTop()
                } else if songs.isEmpty {
                    if loading {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        LibraryUnavailableView(title: "Нет песен",
                                               systemImage: "music.note",
                                               message: "Песни появятся здесь, когда будут в вашей библиотеке.")
                            .emptyStatePinnedToTop()
                    }
                } else if processedSongs.isEmpty {
                    ContentUnavailableView("Ничего не найдено",
                                           systemImage: "magnifyingglass",
                                           // swiftlint:disable:next line_length
                                            description: Text("Попробуйте изменить запрос или параметры фильтра.".localized))
                        .emptyStatePinnedToTop()
                } else {
                    SongTable(songs: processedSongs,
                              sortOrder: $sortOrder,
                              columnCustomization: $columnCustomization)
                        .environment(app)
                }
            }

            // Footer spinner while more chunks stream in; the table above is
            // already interactive and populated with everything fetched so far.
            if isLoadingMore && !processedSongs.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Загружаем остальные песни…".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
        }
        .task {
            reprocess()
            if !app.library.songsLoaded {
                await load()
            } else {
                loading = false
            }
        }
        .refreshable { await load(isRefresh: true) }
        .onReceive(NotificationCenter.default.publisher(for: .foregroundRefreshRequested)) { _ in
            if loadError != nil {
                Task { await load() }
            }
        }
        .onChange(of: searchText) { scheduleReprocess() }
        .onChange(of: favoritesOnly) { reprocess() }
        .onChange(of: sortOrder) { reprocess() }
    }

    /// Filters by the favorites toggle and search field — into the cached
    /// `processedSongs`. The heavy filter runs off the main actor so a huge
    /// library doesn't stall the UI; results are parented back by a generation
    /// token that discards stale work. Re-entry while a pass is already running
    /// just marks the result dirty so the running pass picks up the newest data
    /// (coalesces the per-chunk calls from `load()`).
    ///
    /// Sorting is also done here, off the main thread. The alternative — letting
    /// `Table` sort internally and swapping in the full freshly-ordered array —
    /// makes SwiftUI diff and re-materialize every row through the AppKit
    /// coordinator on the main thread (a multi-second freeze per chunk). Sorting
    /// once here keeps the passed-in array stable, and `SongTable` renders only
    /// a lazy window of it so the table never materializes the whole library.
    private func reprocess() {
        guard !reprocessing else { reprocessDirty = true; return }
        let base = songs
        // Empty library: nothing to filter or sort, and there is no point
        // spawning a detached task on an empty snapshot — when it later applies
        // it would flash `processedSongs = []` (i.e. "Ничего не найдено") while
        // the first chunks are still streaming in. Sync-set and bail; per-chunk
        // calls after the first page lands run the real pass.
        if base.isEmpty {
            processedSongs = []
            return
        }
        reprocessing = true
        let generation = reprocessGeneration + 1
        reprocessGeneration = generation

        // Snapshot all inputs synchronously on the main actor.
        let onlyFav = favoritesOnly
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let order = sortOrder
        var starredIDs: Set<String>?
        if onlyFav { starredIDs = Set(base.filter { app.isStarred($0) }.map(\.id)) }

        reprocessTask?.cancel()
        reprocessTask = Task.detached(priority: .utility) { [self] in
            let result = Self.compute(base, favoritesOnly: onlyFav, starredIDs: starredIDs,
                                      query: query, sortOrder: order)
            await MainActor.run {
                guard !Task.isCancelled, self.reprocessGeneration == generation else {
                    self.reprocessing = false
                    if self.reprocessDirty {
                        self.reprocessDirty = false
                        self.reprocess()
                    }
                    return
                }
                self.processedSongs = result.processed
                if !result.searchable.isEmpty {
                    self.searchable.merge(result.searchable) { _, new in new }
                }
                self.reprocessing = false
                if self.reprocessDirty {
                    self.reprocessDirty = false
                    self.reprocess()
                }
            }
        }
    }

    /// Pure, off-main filter + sort. Builds the lowercased searchable string
    /// cache as a side effect so it is reused across keystrokes. Applies the
    /// column comparators in `sortOrder` so the array handed to `SongTable` is
    /// already ordered — the table never re-sorts (and never swaps) the whole
    /// library itself.
    nonisolated private static func compute(
        _ source: [SubsonicSong], favoritesOnly: Bool, starredIDs: Set<String>?,
        query: String, sortOrder: [KeyPathComparator<SubsonicSong>]
    ) -> (processed: [SubsonicSong], searchable: [String: String]) {
        var list = source
        if favoritesOnly, let starred = starredIDs {
            list = list.filter { starred.contains($0.id) }
        }
        var searchable: [String: String] = [:]
        if !query.isEmpty {
            list = list.filter { song in
                searchableText(song, cache: &searchable).contains(query)
            }
        }
        if !sortOrder.isEmpty {
            list.sort(using: sortOrder)
        }
        return (list, searchable)
    }

    /// Builds (and caches) a lowercased searchable string for a song so a
    /// search doesn't rebuild text for the whole library every keystroke.
    nonisolated private static func searchableText(_ song: SubsonicSong, cache: inout [String: String]) -> String {
        if let cached = cache[song.id] { return cached }
        let text = [song.title, song.artist, song.album]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        cache[song.id] = text
        return text
    }

    /// Debounces search-field reprocessing so fast typing doesn't re-sort the
    /// full library on every character.
    private func scheduleReprocess() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            reprocess()
        }
    }

    private func songText(_ text: String?) -> String { text ?? "" }

    /// Loads the whole song library in chunks, rendering each page as it
    /// arrives. Navidrome has no "all songs" endpoint, so this pages through
    /// `search3` with a `*` query until the server returns fewer songs than
    /// requested. The table stays live throughout: every fetched page is
    /// appended to the shared library and reprocessed immediately.
    private func load(isRefresh: Bool = false) async {
        guard let client = app.client else { return }
        loadError = nil
        // During a pull-to-refresh keep the already-loaded table visible; the
        // spinner only replaces content on the initial empty load.
        if isRefresh {
            app.library.songs = []
            // An interrupted refresh (tab switched mid-paging) must not leave the
            // store marked loaded with zero songs — the next visit would skip the
            // fetch and render a false "Нет песен" empty page.
            app.library.songsLoaded = false
            searchable.removeAll(keepingCapacity: true)
            loading = true
        }
        if songs.isEmpty { loading = true } else { loading = false }
        isLoadingMore = true
        defer {
            loading = false
            isLoadingMore = false
        }
        var seen = Set(songs.map(\.id))
        var offset = songs.count
        while true {
            if Task.isCancelled { break }
            let batch: [SubsonicSong]
            do {
                batch = try await client.search3(query: "*", songCount: chunkSize, songOffset: offset).songs
            } catch {
                // A failed page is an error, not an empty library: surface
                // retry instead of the "Нет песен" empty state. Only the
                // view decides it's worth showing (no songs loaded yet).
                loadError = error.localizedDescription
                break
            }
            // Collect the chunk into an intermediate array then append once, so
            // the whole page lands as a single observation event instead of one
            // per song row (13k-row libraries made the per-append invalidation
            // cost visible).
            var newSongs: [SubsonicSong] = []
            newSongs.reserveCapacity(batch.count)
            var added = false
            for song in batch where seen.insert(song.id).inserted {
                newSongs.append(song)
                added = true
            }
            if added {
                app.library.songs.append(contentsOf: newSongs)
            }
            // Make each chunk visible as soon as it lands, without waiting for
            // the rest of the library.
            if added {
                searchable.removeAll(keepingCapacity: true)
                reprocess()
            }
            if batch.isEmpty || batch.count < chunkSize {
                // Natural end of the library: mark the store loaded so revisits
                // skip the fetch. Failure and cancellation exit through their
                // own `break`s and leave it unset (empty ≠ error).
                app.library.songsLoaded = true
                break
            }
            offset += batch.count
            await Task.yield()
        }
    }
}
