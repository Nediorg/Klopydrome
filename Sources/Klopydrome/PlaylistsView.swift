import SwiftUI
import NavidromeClient

struct PlaylistsView: View {
    @Environment(AppState.self) private var app

    private var playlists: [PlaylistSummary] { app.library.playlists }
    @State private var loading = true
    @State private var smartRenamePresented = false
    @State private var smartRenameName: String = ""
    @State private var smartRenameID: String = ""
    @State private var confirmingDeleteID: String?
    @State private var confirmingDeleteSmart: SmartPlaylist?

    @State private var searchText = ""
    @State private var favoritesOnly = false

    private let gap: CGFloat = 16
    private let minCard: CGFloat = 165

    private let playlistPageSize = 100
    @State private var displayedPlaylistCount = 100

    private var filteredPlaylists: [PlaylistSummary] {
        var list = playlists
        if favoritesOnly {
            list = list.filter { app.isFollowed($0) }
        }
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            list = list.filter {
                ($0.displayName + " " + ($0.owner ?? "")).lowercased().contains(query)
            }
        }
        return list
    }

    private var filteredSmartPlaylists: [SmartPlaylist] {
        if favoritesOnly { return [] }
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return app.smartPlaylists }
        return app.smartPlaylists.filter {
            $0.name.lowercased().contains(query)
        }
    }

    private var displayedPlaylists: [PlaylistSummary] {
        Array(filteredPlaylists.prefix(displayedPlaylistCount))
    }

    var body: some View {
        VStack(spacing: 0) {
            LibraryHeader(title: "All Playlists", searchText: $searchText) {
                Picker("Show".localized, selection: $favoritesOnly) {
                    Text("All Playlists".localized).tag(false)
                    Text("Favorites only".localized).tag(true)
                }
                .pickerStyle(.inline)
            }
            .background(.ultraThinMaterial)
            .overlay(alignment: .bottom) { Divider().opacity(0.35) }
            .zIndex(1)

            Group {
                if loading && playlists.isEmpty && app.smartPlaylists.isEmpty {
                    initialLoadingGrid
                } else if playlists.isEmpty && app.smartPlaylists.isEmpty {
                    ContentUnavailableView {
                        Label("No Playlists".localized, systemImage: "music.note.list")
                    } description: {
                        Text("Create a playlist to see it here.".localized)
                    } actions: {
                        Button("Create Playlist".localized) {
                            guard app.confirmOfflineAction() else { return }
                            app.creatingPlaylistSongs = []
                            app.isCreatingPlaylist = true
                        }
                    }
                    .emptyStatePinnedToTop()
                } else if filteredPlaylists.isEmpty && filteredSmartPlaylists.isEmpty {
                    ContentUnavailableView(
                        "Nothing Found".localized,
                        systemImage: "magnifyingglass",
                        description: Text("Try changing the query or filter settings.".localized)
                    )
                    .emptyStatePinnedToTop()
                } else {
                    GeometryReader { geo in
                        let available = geo.size.width - 48
                        let count = max(1, Int((available + gap) / (minCard + gap)))
                        let rawWidth = (available - CGFloat(count - 1) * gap) / CGFloat(count)
                        let cardWidth = floor(rawWidth)
                        let cols = Array(repeating: GridItem(.fixed(cardWidth), spacing: gap), count: count)
                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
                                if !filteredSmartPlaylists.isEmpty {
                                    smartSection(cols: cols, cardWidth: cardWidth)
                                }

                                LazyVGrid(columns: cols, spacing: gap) {
                                    ForEach(displayedPlaylists) { playlist in
                                        Button {
                                            app.openPlaylist(playlist)
                                        } label: {
                                            PlaylistTile(
                                                playlist: playlist,
                                                width: cardWidth,
                                                onRename: { rename(playlist) },
                                                onEditRules: {
                                                    let server = ServerSmartPlaylist(summary: playlist)
                                                    app.openSmartPlaylistEditor(server: server)
                                                },
                                                onDelete: { confirmingDeleteID = playlist.id }
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    if displayedPlaylistCount < filteredPlaylists.count {
                                        Color.clear.frame(height: 1)
                                            .gridCellColumns(count)
                                            .onAppear {
                                                displayedPlaylistCount = min(
                                                    displayedPlaylistCount + playlistPageSize,
                                                    filteredPlaylists.count
                                                )
                                            }
                                    }
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 20)
                        }
                        .scrollClipDisabled()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .refreshable {
            if app.isOfflineSession {
                _ = await app.reconnect()
            } else {
                await load()
            }
        }
        .task(id: app.isConnected) { await loadIfNeeded() }
        .onChange(of: searchText) { displayedPlaylistCount = playlistPageSize }
        .onChange(of: favoritesOnly) { displayedPlaylistCount = playlistPageSize }
        .confirmationDialog(
            "Delete Playlist?".localized,
            isPresented: Binding(
                get: { confirmingDeleteID != nil },
                set: { if !$0 { confirmingDeleteID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete".localized, role: .destructive) {
                if let id = confirmingDeleteID, let playlist = playlists.first(where: { $0.id == id }) {
                    delete(playlist)
                }
                confirmingDeleteID = nil
            }
            Button("Cancel".localized, role: .cancel) { confirmingDeleteID = nil }
        }
        .alert("Rename Smart Playlist".localized, isPresented: $smartRenamePresented) {
            TextField("Playlist Name".localized, text: $smartRenameName)
            Button("Rename".localized) { smartRename(smartRenameID, smartRenameName) }
            Button("Cancel".localized, role: .cancel) {}
        }
        .confirmationDialog(
            "Delete Smart Playlist?".localized,
            isPresented: Binding(
                get: { confirmingDeleteSmart != nil },
                set: { if !$0 { confirmingDeleteSmart = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete".localized, role: .destructive) {
                if let smart = confirmingDeleteSmart {
                    app.deleteSmartPlaylist(id: smart.id)
                }
                confirmingDeleteSmart = nil
            }
            Button("Cancel".localized, role: .cancel) { confirmingDeleteSmart = nil }
        }
    }

    private var initialLoadingGrid: some View {
        SkeletonCardGrid(
            count: 12,
            minCard: minCard,
            gap: gap,
            accessibilityLabel: "Loading playlists".localized
        )
    }

    private func smartSection(cols: [GridItem], cardWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Smart Playlists".localized)
                .font(.title3.bold())
                .foregroundStyle(.secondary)
            LazyVGrid(columns: cols, spacing: gap) {
                ForEach(filteredSmartPlaylists) { smart in
                    Button {
                        app.openSmartPlaylist(smart)
                    } label: {
                        SmartPlaylistTile(playlist: smart, width: cardWidth)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        SmartPlaylistContextMenuItems(playlist: smart) {
                            app.openSmartPlaylistEditor(playlist: smart)
                        } onRename: {
                            smartRenameID = smart.id
                            smartRenameName = smart.name
                            smartRenamePresented = true
                        } onDelete: {
                            confirmingDeleteSmart = smart
                        }
                    }
                }
            }
        }
    }

    private func loadIfNeeded() async {
        guard !app.library.playlistsLoaded else {
            loading = false
            return
        }
        await load()
    }

    private func load() async {
        if app.library.playlists.isEmpty { loading = true }
        displayedPlaylistCount = playlistPageSize
        defer { loading = false }
        guard app.client != nil else { return }
        await app.refreshPlaylists()
    }

    private func delete(_ playlist: PlaylistSummary) {
        guard let client = app.client else { return }
        Task {
            try? await client.deletePlaylist(id: playlist.id)
            await load()
        }
    }

    private func rename(_ playlist: PlaylistSummary) {
        app.openCreatePlaylist(existing: playlist)
    }

    private func smartRename(_ id: String, _ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        app.renameSmartPlaylist(id: id, name: trimmed)
    }
}

struct PlaylistTile: View {
    let playlist: PlaylistSummary
    var width: CGFloat?
    var onRename: (() -> Void)?
    var onEditRules: (() -> Void)?
    var onDelete: (() -> Void)?

    @Environment(AppState.self) private var app
    @State private var hovering = false
    @State private var hoverTracker = HoverTracker()

    private var isFollowed: Bool { app.isFollowed(playlist) }

    private var fallbackPreset: PlaylistCoverPreset {
        PlaylistCoverPreset.preset(for: playlist.id)
    }

    var body: some View {
        let cardWidth = width ?? 165
        MediaCard(
            width: cardWidth,
            title: playlist.displayName,
            subtitle: playlist.owner ?? "Playlist".localized,
            reservesTitleLines: true
        ) {
            if let coverArt = playlist.coverArt, !coverArt.isEmpty {
                CoverArtView(coverArt: coverArt, size: cardWidth, cornerRadius: 6, shadow: true)
            } else {
                CoverPresetView(preset: fallbackPreset, size: cardWidth, title: playlist.displayName)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
            }
        } trailingBadge: {
            if hovering || isFollowed {
                Button {
                    app.toggleFollow(playlist)
                } label: {
                    Image(systemName: isFollowed ? "star.fill" : "star")
                        .font(.system(size: 13))
                        .foregroundStyle(isFollowed ? AMColor.accent : .white)
                        .padding(5)
                        .background(Circle().fill(.black.opacity(0.35)))
                }
                .buttonStyle(.plain)
                .padding(6)
                .help(isFollowed ? "Remove from Favorites".localized : "Add to Favorites".localized)
                .accessibilityLabel(
                    isFollowed ? "Remove from Favorites".localized : "Add to Favorites".localized
                )
                .transition(.opacity)
            }
        }
        .onHover { isInside in
            hoverTracker.isInside = isInside
            if isInside {
                if !ScrollGate.shared.isScrolling {
                    hovering = true
                }
            } else {
                if hovering {
                    hovering = false
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ScrollGate.scrollDidEnd)) { _ in
            if hoverTracker.isInside && !hovering {
                hovering = true
            }
        }
        .contextMenu {
            PlaylistContextMenuItems(
                playlist: playlist,
                onRename: onRename ?? {},
                onEditRules: onEditRules ?? {},
                onDelete: onDelete ?? {}
            )
        }
    }
}

struct SmartPlaylistTile: View {
    let playlist: SmartPlaylist
    var width: CGFloat?

    var body: some View {
        let cardWidth = width ?? 165
        MediaCard(
            width: cardWidth,
            title: playlist.name,
            subtitle: playlist.ruleSummary,
            reservesTitleLines: true
        ) {
            Image(systemName: "gearshape")
                .font(.system(size: cardWidth * 0.44, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: cardWidth, height: cardWidth)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.gray.opacity(0.12))
                )
        }
    }
}