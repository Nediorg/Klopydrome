import SwiftUI
import NavidromeClient

struct SongsView: View {
    @Environment(AppState.self) private var app

    private let chunkSize = 500

    private var songs: [SubsonicSong] { app.library.songs }
    private var displaySongs: [SubsonicSong] {
        if !processedSongs.isEmpty {
            return processedSongs
        }
        if searchText.isEmpty && !favoritesOnly {
            return songs
        }
        return []
    }
    @State private var loading = true
    @State private var isLoadingMore = false
    @State private var loadError: String?
    @State private var favoritesOnly = false
    @State private var searchText = ""
    @State private var sortOrder: [KeyPathComparator<SubsonicSong>] = [
        KeyPathComparator(\.title, order: .forward),
    ]
    @State private var processedSongs: [SubsonicSong] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var reprocessTask: Task<Void, Never>?
    @State private var reprocessGeneration = 0
    @State private var reprocessDirty = false
    @State private var reprocessing = false
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
                Picker("Show".localized, selection: $favoritesOnly) {
                    Text("All Songs".localized).tag(false)
                    Text("Favorites only".localized).tag(true)
                }
                .pickerStyle(.inline)
            }

            Group {
                if let loadError, songs.isEmpty {
                    LibraryUnavailableView(title: "Failed to load".localized,
                                           systemImage: "wifi.exclamationmark",
                                           message: loadError,
                                           retry: { Task { await load() } })
                        .emptyStatePinnedToTop()
                } else if songs.isEmpty {
                    if loading {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        LibraryUnavailableView(
                            title: "No Songs".localized,
                            systemImage: "music.note",
                            message: "Songs will appear here when they're in your library.".localized
                        )
                        .emptyStatePinnedToTop()
                    }
                } else if displaySongs.isEmpty {
                    if reprocessing || (!app.library.songsLoaded && loading) {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ContentUnavailableView("Nothing Found".localized,
                                               systemImage: "magnifyingglass",
                                                description: Text("Try changing the query or filter settings.".localized))
                            .emptyStatePinnedToTop()
                    }
                } else {
                    SongTable(songs: displaySongs,
                              sortOrder: $sortOrder,
                              columnCustomization: $columnCustomization)
                        .environment(app)
                }
            }

            if isLoadingMore && !displaySongs.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading remaining songs…".localized)
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

    private func reprocess() {
        guard !reprocessing else { reprocessDirty = true; return }
        let base = songs
        if base.isEmpty {
            processedSongs = []
            return
        }
        reprocessing = true
        let generation = reprocessGeneration + 1
        reprocessGeneration = generation

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

    private func scheduleReprocess() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            reprocess()
        }
    }

    private func songText(_ text: String?) -> String { text ?? "" }

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
        var lastReprocessTime = Date()
        while !Task.isCancelled {
            let batch: [SubsonicSong]
            do {
                batch = try await client.search3(query: "*", songCount: chunkSize, songOffset: offset).songs
            } catch {
                loadError = error.localizedDescription
                break
            }
            if appendBatch(batch, seen: &seen) {
                let now = Date()
                if now.timeIntervalSince(lastReprocessTime) >= 1.0 || batch.count < chunkSize {
                    lastReprocessTime = now
                    reprocess()
                }
            }
            if batch.isEmpty || batch.count < chunkSize {
                app.library.songsLoaded = true
                await app.persistSongsToDisk()
                reprocess()
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
        if !newSongs.isEmpty {
            app.library.songs.append(contentsOf: newSongs)
        }
        return added
    }
}
