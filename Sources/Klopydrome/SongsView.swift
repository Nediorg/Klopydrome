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
    private let chunkSize = 500

    private var songs: [SubsonicSong] { app.library.songs }
    /// Filtered + sorted result to display. Falls back to raw `songs` on first
    /// appearance while background sort/filter computation is running, avoiding
    /// a flash of empty state or "Ничего не найдено".
    private var displaySongs: [SubsonicSong] {
        if !processedSongs.isEmpty {
            return processedSongs
        }
        if searchText.isEmpty && !favoritesOnly {
            var seen = Set<String>()
            return songs.filter { seen.insert($0.id).inserted }
        }
        return []
    }
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
        for column in SongColumn.allCases {
            customization[visibility: column.id] = SongColumn.defaults.contains(column) ? .visible : .hidden
        }
        return customization
    }()

    var body: some View {
        VStack(spacing: 0) {
            LibraryHeader(
                title: "",
                searchText: $searchText,
                isLoading: isLoadingMore,
                filteredCount: searchText.isEmpty ? nil : displaySongs.count,
                totalCount: searchText.isEmpty ? nil : songs.count
            ) {
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
                } else if displaySongs.isEmpty {
                    if reprocessing || (!app.library.songsLoaded && loading) {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ContentUnavailableView("Ничего не найдено",
                                               systemImage: "magnifyingglass",
                                               // swiftlint:disable:next line_length
                                                description: Text("Попробуйте изменить запрос или параметры фильтра.".localized))
                            .emptyStatePinnedToTop()
                    }
                } else {
                    SongTable(songs: displaySongs,
                              sortOrder: $sortOrder,
                              columnCustomization: $columnCustomization)
                        .environment(app)
                }
            }

            // Footer spinner while more chunks stream in; the table above is
            // already interactive and populated with everything fetched so far.
            if isLoadingMore && !displaySongs.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Загружаем остальные песни…".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            if !app.library.songsLoaded {
                await app.restoreCachedSongsIfNeeded()
            }
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
        reprocessTask = Task.detached(priority: .userInitiated) {
            guard !Task.isCancelled else { return }
            let result = Self.compute(base, favoritesOnly: onlyFav, starredIDs: starredIDs,
                                      query: query, sortOrder: order)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard !Task.isCancelled, reprocessGeneration == generation else {
                    reprocessing = false
                    if reprocessDirty {
                        reprocessDirty = false
                        reprocess()
                    }
                    return
                }
                processedSongs = result
                reprocessing = false
                if reprocessDirty {
                    reprocessDirty = false
                    reprocess()
                }
            }
        }
    }

    /// Pure, off-main filter + sort. Filters on-the-fly directly across song
    /// fields without pinning duplicate searchable strings in memory. Applies the
    /// column comparators in `sortOrder` so the array handed to `SongTable` is
    /// already ordered — the table never re-sorts (and never swaps) the whole
    /// library itself.
    nonisolated private static func compute(
        _ source: [SubsonicSong], favoritesOnly: Bool, starredIDs: Set<String>?,
        query: String, sortOrder: [KeyPathComparator<SubsonicSong>]
    ) -> [SubsonicSong] {
        var seenIDs = Set<String>()
        var list = source.filter { seenIDs.insert($0.id).inserted }
        if favoritesOnly, let starred = starredIDs {
            list = list.filter { starred.contains($0.id) }
        }
        guard !Task.isCancelled else { return [] }
        if !query.isEmpty {
            let terms = query.split(separator: " ")
            list = list.filter { song in
                let title = song.title ?? ""
                let artist = song.artist ?? ""
                let album = song.album ?? ""
                return terms.allSatisfy { term in
                    title.localizedCaseInsensitiveContains(term) ||
                    artist.localizedCaseInsensitiveContains(term) ||
                    album.localizedCaseInsensitiveContains(term)
                }
            }
        }
        guard !Task.isCancelled else { return [] }
        if !sortOrder.isEmpty {
            list.sort(using: sortOrder)
        }
        return list
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
        if isRefresh {
            app.library.songs = []
            app.library.songsLoaded = false
            loading = true
        } else {
            loading = songs.isEmpty
        }
        isLoadingMore = true
        defer {
            loading = false
            isLoadingMore = false
        }
        var seen = Set(songs.map(\.id))
        var offset = songs.count
        while !Task.isCancelled {
            let batch: [SubsonicSong]
            do {
                batch = try await client.search3(query: "*", songCount: chunkSize, songOffset: offset).songs
            } catch {
                loadError = error.localizedDescription
                break
            }
            if appendBatch(batch, seen: &seen) {
                reprocess()
            }
            if batch.isEmpty || batch.count < chunkSize {
                app.library.songsLoaded = true
                await app.persistSongsToDisk()
                break
            }
            offset += batch.count
            await Task.yield()
        }
    }

    private func appendBatch(_ batch: [SubsonicSong], seen: inout Set<String>) -> Bool {
        var newSongs: [SubsonicSong] = []
        newSongs.reserveCapacity(batch.count)
        var added = false
        for song in batch where seen.insert(song.id).inserted {
            newSongs.append(song)
            added = true
        }
        if added {
            let existing = Set(app.library.songs.map(\.id))
            let strictlyNew = newSongs.filter { !existing.contains($0.id) }
            if !strictlyNew.isEmpty {
                app.library.songs.append(contentsOf: strictlyNew)
            }
        }
        return added
    }
}
