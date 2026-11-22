import SwiftUI
import NavidromeClient

struct PlaylistsView: View {
    @Environment(AppState.self) private var app

    private var playlists: [PlaylistSummary] { app.library.playlists }
    @State private var loading = true
    @State private var confirmingDeleteID: String?

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
                if loading && playlists.isEmpty {
                    initialLoadingGrid
                } else if playlists.isEmpty {
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
                } else if filteredPlaylists.isEmpty {
                    ContentUnavailableView(
                        "Nothing Found".localized,
                        systemImage: "magnifyingglass",
                        description: Text("Try changing the query or filter settings.".localized)
                    )
                    .emptyStatePinnedToTop()
                } else {
                    GeometryReader { geo in
                        let grid = AdaptiveGridGeometry(availableWidth: geo.size.width - 48, minCard: minCard, gap: gap)
                        ScrollView {
                            LazyVGrid(columns: grid.columns, spacing: gap) {
                                ForEach(displayedPlaylists) { playlist in
                                    Button {
                                        app.openPlaylist(playlist)
                                    } label: {
                                        PlaylistTile(
                                            playlist: playlist,
                                            width: grid.cardWidth,
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
                                        .gridCellColumns(grid.columnCount)
                                        .onAppear {
                                            displayedPlaylistCount = min(
                                                displayedPlaylistCount + playlistPageSize,
                                                filteredPlaylists.count
                                            )
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
    }

    private var initialLoadingGrid: some View {
        SkeletonCardGrid(
            count: 12,
            minCard: minCard,
            gap: gap,
            accessibilityLabel: "Loading playlists".localized
        )
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
        Task {
            await app.deletePlaylist(playlist)
            await load()
        }
    }

    private func rename(_ playlist: PlaylistSummary) {
        app.openCreatePlaylist(existing: playlist)
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
    @State private var isInside = false

    private var isFollowed: Bool { app.isFollowed(playlist) }

    private var fallbackPreset: PlaylistCoverPreset {
        PlaylistCoverPreset.preset(for: playlist.id)
    }

    private var subtitleText: String {
        if playlist.isSmart {
            return playlist.owner.map { "\($0) · \("Smart Playlist".localized)" } ?? "Smart Playlist".localized
        }
        return playlist.owner ?? "Playlist".localized
    }

    var body: some View {
        let cardWidth = width ?? 165
        MediaCard(
            width: cardWidth,
            title: playlist.displayName,
            subtitle: subtitleText,
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
        .onHover { inside in
            isInside = inside
            if inside {
                if !ScrollGate.shared.isScrolling {
                    hovering = true
                }
            } else {
                if hovering {
                    hovering = false
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ScrollGate.scrollDidStart)) { _ in
            if hovering {
                hovering = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ScrollGate.scrollDidEnd)) { _ in
            if isInside && !hovering {
                hovering = true
            }
        }
        .onDisappear {
            isInside = false
            hovering = false
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