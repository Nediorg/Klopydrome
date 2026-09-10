import SwiftUI
import NavidromeClient

struct PlaylistsView: View {
    @Environment(AppState.self) private var app

    private var playlists: [PlaylistSummary] { app.library.playlists }
    @State private var loading = true
    @State private var activeSheet: ActiveSheet?
    @State private var smartRenamePresented = false
    @State private var smartRenameName: String = ""
    @State private var smartRenameID: String = ""
    @State private var confirmingDeleteID: String?
    @State private var confirmingDeleteSmart: SmartPlaylist?

    /// Presentations owned by this view. Merged into one `.sheet(item:)`
    /// because SwiftUI only honours the last `.sheet` modifier on a view.
    enum ActiveSheet: Identifiable {
        case edit(PlaylistSummary)
        case smart(SmartPlaylist?)
        case serverSmart(ServerSmartPlaylist)

        var id: String {
            switch self {
            case .edit(let playlist):
                return "edit-\(playlist.id)"
            case .smart(let smart):
                return "smart-\(smart?.id ?? "new")"
            case .serverSmart(let server):
                return "server-smart-\(server.id)"
            }
        }
    }

    var body: some View {
        Group {
            if loading && playlists.isEmpty && app.smartPlaylists.isEmpty {
                initialLoadingGrid
            } else if playlists.isEmpty && app.smartPlaylists.isEmpty {
                ContentUnavailableView {
                    Label("Нет плейлистов", systemImage: "music.note.list")
                } description: {
                    Text("Создайте плейлист, чтобы увидеть его здесь.".localized)
                } actions: {
                    Button("Создать плейлист".localized) {
                        app.creatingPlaylistSongs = []
                        app.isCreatingPlaylist = true
                    }
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        if !app.smartPlaylists.isEmpty {
                            smartSection
                        }

                        LazyVGrid(columns: columns, alignment: .leading, spacing: 32) {
                            ForEach(playlists) { playlist in
                                NavigationLink(value: playlist) {
                                    PlaylistTile(playlist: playlist)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    PlaylistContextMenuItems(playlist: playlist) {
                                        rename(playlist)
                                    } onEditRules: {
                                        activeSheet = .serverSmart(ServerSmartPlaylist(summary: playlist))
                                    } onDelete: {
                                        confirmingDeleteID = playlist.id
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                }
                .scrollClipDisabled()
                .refreshable { await load() }
            }
        }
        .task(id: app.isConnected) { await loadIfNeeded() }
        .navigationDestination(for: SmartPlaylist.self) { SmartPlaylistDetailView(playlist: $0) }
        .confirmationDialog(
            "Удалить плейлист?",
            isPresented: Binding(
                get: { confirmingDeleteID != nil },
                set: { if !$0 { confirmingDeleteID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                if let id = confirmingDeleteID, let playlist = playlists.first(where: { $0.id == id }) {
                    delete(playlist)
                }
                confirmingDeleteID = nil
            }
            Button("Отмена", role: .cancel) { confirmingDeleteID = nil }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .edit(let playlist):
                CreatePlaylistModal(songs: [], existing: playlist)
            case .smart(let target):
                SmartPlaylistEditorView(playlist: target)
            case .serverSmart(let target):
                SmartPlaylistEditorView(playlist: nil, server: target)
            }
        }
        .alert("Переименовать умный плейлист", isPresented: $smartRenamePresented) {
            TextField("Название плейлиста", text: $smartRenameName)
            Button("Переименовать") { smartRename(smartRenameID, smartRenameName) }
            Button("Отмена", role: .cancel) {}
        }
        .confirmationDialog(
            "Удалить умный плейлист?",
            isPresented: Binding(
                get: { confirmingDeleteSmart != nil },
                set: { if !$0 { confirmingDeleteSmart = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                if let smart = confirmingDeleteSmart {
                    app.deleteSmartPlaylist(id: smart.id)
                }
                confirmingDeleteSmart = nil
            }
            Button("Отмена", role: .cancel) { confirmingDeleteSmart = nil }
        }
    }

    /// Responsive grid of large, square playlist tiles.
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 24)]
    }

    /// Keeps the first tab visit spatially stable while the playlist manifest is
    /// in flight, replacing the former page-wide spinner with useful structure.
    private var initialLoadingGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 32) {
                ForEach(0..<8, id: \.self) { _ in
                    PlaylistTilePlaceholder()
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
        .scrollClipDisabled()
        .accessibilityLabel("Загрузка плейлистов")
    }

    private var smartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Умные плейлисты".localized)
                .font(.title3.bold())
                .foregroundStyle(.secondary)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 32) {
                ForEach(app.smartPlaylists) { smart in
                    NavigationLink(value: smart) {
                        SmartPlaylistTile(playlist: smart)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        SmartPlaylistContextMenuItems(playlist: smart) {
                            activeSheet = .smart(smart)
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

    /// Fetches the playlist list only when it has never been loaded, so revisits
    /// are instant. Pull-to-refresh still forces a full reload.
    private func loadIfNeeded() async {
        guard !app.library.playlistsLoaded else { return }
        await load()
    }

    private func load() async {
        guard app.client != nil else { return }
        if app.library.playlists.isEmpty { loading = true }
        defer { loading = false }
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
        activeSheet = .edit(playlist)
    }

    private func smartRename(_ id: String, _ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        app.renameSmartPlaylist(id: id, name: trimmed)
    }
}

/// Large, square playlist tile: artwork with the title and creator underneath.
struct PlaylistTilePlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .aspectRatio(1, contentMode: .fit)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.primary.opacity(0.07))
                .frame(width: 132, height: 13)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.primary.opacity(0.05))
                .frame(width: 88, height: 10)
        }
        .accessibilityHidden(true)
    }
}

struct PlaylistTile: View {
    let playlist: PlaylistSummary

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                CoverArtView(coverArt: playlist.coverArt, size: geo.size.width, cornerRadius: 10, shadow: true)
            }
            .aspectRatio(1, contentMode: .fit)

            VStack(alignment: .leading, spacing: 1) {
                Text(playlist.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(playlist.owner ?? "Плейлист")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
        .contentShape(Rectangle())
        .scaleEffect(hovering ? 1.03 : 1)
        .zIndex(hovering ? 1 : 0)
        .animation(.snappy(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
    }
}

/// Square tile for a smart playlist: outline gear artwork with rules beneath.
struct SmartPlaylistTile: View {
    let playlist: SmartPlaylist

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "gearshape")
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.gray.opacity(0.12))
                )
                .aspectRatio(1, contentMode: .fit)

            VStack(alignment: .leading, spacing: 1) {
                Text(playlist.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(playlist.ruleSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
        .contentShape(Rectangle())
        .scaleEffect(hovering ? 1.03 : 1)
        .zIndex(hovering ? 1 : 0)
        .animation(.snappy(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
    }
}