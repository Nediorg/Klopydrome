import SwiftUI
import NavidromeClient

struct SidebarView: View {
    @Environment(AppState.self) private var app

    /// Common selection type for the sidebar List. Playlist selection is keyed
    /// by the playlist's stable id string, not the full struct: the synthesized
    /// Hashable of `PlaylistSummary` changes when the list reloads (new
    /// instances), which made subsequent playlist clicks silently ignored.
    enum Selection: Hashable {
        case section(NavigationState.Section)
        case playlistID(String)
    }

    @State private var selection: Selection?
    @State private var activeSheet: SidebarSheet?
    @State private var confirmingDeleteID: String?

    /// Presentations owned by the sidebar. Merged into one `.sheet(item:)`
    /// because SwiftUI only honours the last `.sheet` modifier on a view.
    enum SidebarSheet: Identifiable {
        case newPlaylist
        case newSmartPlaylist
        case editPlaylist(PlaylistSummary)
        case editServerSmartPlaylist(ServerSmartPlaylist)

        var id: String {
            switch self {
            case .newPlaylist: return "new"
            case .newSmartPlaylist: return "smart"
            case .editPlaylist(let playlist): return "edit-\(playlist.id)"
            case .editServerSmartPlaylist(let playlist): return "server-smart-\(playlist.id)"
            }
        }
    }

    private var playlists: [PlaylistSummary] { app.library.playlists }

    var body: some View {
        List(selection: $selection) {
            Section {
                sidebarRow("Главная", .home)
            }

            Section("Библиотека") {
                sidebarRow("Недавно добавленные", .recentlyAdded)
                sidebarRow("Артисты", .artists)
                sidebarRow("Альбомы", .albums)
                sidebarRow("Песни", .songs)
                sidebarRow("Избранное", .favorites)
            }

            Section {
                playlistRow("Все плейлисты",
                            icon: icon(for: .playlists),
                            isSelected: selection == .section(.playlists))
                    .tag(Selection.section(.playlists))
                    .contentShape(Rectangle())
                    .simultaneousGesture(TapGesture().onEnded { select(.section(.playlists)) })
                    .contextMenu { playlistContextMenu }
                ForEach(personalPlaylists) { playlist in
                    playlistRow(playlist.displayName,
                                icon: playlist.isSmart ? "gearshape" : "music.note.list",
                                isSelected: selection == .playlistID(playlist.id))
                        .lineLimit(1)
                        .tag(Selection.playlistID(playlist.id))
                        .contentShape(Rectangle())
                        .simultaneousGesture(TapGesture().onEnded { select(.playlistID(playlist.id)) })
                        .contextMenu {
                            PlaylistContextMenuItems(playlist: playlist) {
                                beginRename(playlist)
                            } onEditRules: {
                                editRules(playlist)
                            } onDelete: {
                                confirmingDeleteID = playlist.id
                            }
                        }
                }
            } header: {
                Text("Плейлисты".localized)
                    .contextMenu { playlistContextMenu }
            }

            Section {
                ForEach(sharedPlaylists) { playlist in
                    playlistRow(playlist.displayName,
                                icon: "arrow.turn.down.right",
                                isSelected: selection == .playlistID(playlist.id))
                        .lineLimit(1)
                        .tag(Selection.playlistID(playlist.id))
                        .contentShape(Rectangle())
                        .simultaneousGesture(TapGesture().onEnded { select(.playlistID(playlist.id)) })
                        .contextMenu {
                            PlaylistContextMenuItems(playlist: playlist) {
                                beginRename(playlist)
                            } onEditRules: {
                                editRules(playlist)
                            } onDelete: {
                                confirmingDeleteID = playlist.id
                            }
                        }
                }
            } header: {
                Text("Общие плейлисты".localized)
                    .contextMenu { playlistContextMenu }
            }
        }
        // Native macOS sidebar selection: the system draws the picked row as a
        // rounded pill in the app accent color while the sidebar is focused and
        // neutral gray when it is not (Finder/Music style), inverting the row
        // text/icons to white on the selected row. No AppKit overrides needed.
        .listStyle(.sidebar)
        // Keep rows below the traffic lights without moving the sidebar search field.
        .contentMargins(.top, LayoutMetrics.trafficLightInset, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .background(.thinMaterial, ignoresSafeAreaEdges: .all)
        .navigationSplitViewColumnWidth(
            min: LayoutMetrics.sidebarMinWidth,
            ideal: LayoutMetrics.sidebarIdealWidth,
            max: LayoutMetrics.sidebarMaxWidth
        )
        // Freeze row layout during collapse animation: rows keep full width
        // anchored LEADING and clip toward the divider instead of reflowing.
        // The default center alignment drifts the icons right as the column
        // narrows (centered overflow in a shrinking frame). Leading anchor
        // reads as the native slide-away; user resize drags still reflow
        // normally above the floor. Also skips per-frame List relayout.
        .frame(minWidth: LayoutMetrics.sidebarMinWidth, alignment: .leading)
        .clipped()
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .newPlaylist:
                CreatePlaylistModal(songs: [])
            case .newSmartPlaylist:
                SmartPlaylistEditorView(playlist: nil)
            case .editPlaylist(let playlist):
                CreatePlaylistModal(songs: [], existing: playlist)
            case .editServerSmartPlaylist(let playlist):
                SmartPlaylistEditorView(playlist: nil, server: playlist)
            }
        }
        .confirmationDialog(
            "Удалить плейлист?",
            isPresented: Binding(
                get: { confirmingDeleteID != nil },
                set: { if !$0 { confirmingDeleteID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                if let id = confirmingDeleteID,
                   let playlist = playlists.first(where: { $0.id == id }) {
                    Task { await app.deletePlaylist(playlist) }
                }
                confirmingDeleteID = nil
            }
            Button("Отмена", role: .cancel) { confirmingDeleteID = nil }
        }
        .searchable(text: Bindable(app).nav.searchQuery, placement: .sidebar, prompt: "Искать музыку")
        .submitLabel(.search)
        .onSubmit(of: .search) { submitSearch() }
        .task(id: app.isConnected) { await loadPlaylists() }
        .onChange(of: selection) { _, newValue in
            if let newValue { select(newValue) }
        }
        .onAppear {
            if let selectedPlaylist = app.nav.selectedPlaylist {
                selection = .playlistID(selectedPlaylist.id)
            } else {
                selection = .section(app.nav.selected)
            }
        }
    }

    /// Applies a sidebar selection to app state and signals the detail column
    /// (via `navVersion`) to pop to the selected item's root. Called on every
    /// explicit row tap and on List selection changes, so re-clicking the
    /// already-active item re-navigates instead of being ignored.
    private func select(_ newValue: Selection) {
        selection = newValue
        applySelection(newValue)
        app.nav.navVersion += 1
    }

    /// Applies a sidebar selection to app state. Sections switch the detail
    /// content one-to-one; a playlist selection shows that playlist's detail in
    /// the detail column (via `app.nav.selectedPlaylist`).
    private func applySelection(_ newValue: Selection?) {
        if case .section(let section)? = newValue {
            app.nav.selectedPlaylist = nil
            app.nav.selected = section
        } else if case .playlistID(let id)? = newValue {
            guard let playlist = playlists.first(where: { $0.id == id }) else { return }
            app.nav.selected = .playlists
            app.nav.selectedPlaylist = playlist
        }
    }

    private func loadPlaylists() async {
        await app.refreshPlaylists()
    }

    private var playlistContextMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                activeSheet = .newPlaylist
            } label: {
                Label("Новый плейлист", systemImage: "plus")
            }
            Button {
                activeSheet = .newSmartPlaylist
            } label: {
                Label("Новый умный плейлист", systemImage: "gearshape")
            }
        }
    }

    private func beginRename(_ playlist: PlaylistSummary) {
        activeSheet = .editPlaylist(playlist)
    }

    private func editRules(_ playlist: PlaylistSummary) {
        guard playlist.isSmart else { return }
        activeSheet = .editServerSmartPlaylist(ServerSmartPlaylist(summary: playlist))
    }

    /// Only the current user's own playlists render in the sidebar; curated and
    /// algorithmic collections owned by others are excluded.
    private var personalPlaylists: [PlaylistSummary] {
        guard let username = app.client?.config.username, !username.isEmpty else {
            return playlists
        }
        return playlists.filter { $0.owner == nil || $0.owner == username }
    }

    /// Playlists owned by someone else (shared into the library).
    private var sharedPlaylists: [PlaylistSummary] {
        guard let username = app.client?.config.username, !username.isEmpty else {
            return []
        }
        return playlists.filter { $0.owner != nil && $0.owner != username }
    }

    private func submitSearch() {
        let query = app.nav.searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        app.nav.selected = .search
        app.nav.selectedPlaylist = nil
        // Bump the nav version so a repeated submit re-runs the search even when
        // the query is unchanged (the search view keys its load task on
        // `navVersion`) and pops any pushed detail page so the fresh results are
        // actually visible.
        app.nav.navVersion += 1
    }

    /// Sidebar row with the native look (accent icon, system selection pill)
    /// that re-navigates even when the item is already selected.
    ///
    /// Tahoe (macOS 26) renders sidebar `Label` symbols larger than the row
    /// text. A plain `HStack` bypasses the inflated `LabelStyle` altogether;
    /// a size-only fix via `LabelStyle` forfeits the automatic accent/white
    /// tint (icon stays white), so the `isSelected` tint has to be explicit.
    private func sidebarRow(_ text: String, _ section: NavigationState.Section) -> some View {
        let isSelected = selection == .section(section)
        return HStack(spacing: 6) {
            Image(systemName: icon(for: section))
                .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                .frame(width: 16, height: 16)
            Text(text.localized)
        }
        .tag(Selection.section(section))
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { select(.section(section)) })
    }

    /// Playlist row built as an HStack, NOT a `Label`: the sidebar list style
    /// forces its own tint on Label icons (accent). The explicit dark-gray
    /// resting color preserves the intended playlist appearance, while the
    /// selected icon matches the native white active-row treatment.
    private func playlistRow(_ text: String, icon: String, isSelected: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(isSelected ? .white : Color(nsColor: .darkGray))
                .frame(width: 16, height: 16)
            Text(text)
        }
    }

    /// The outline glyph for a section row; keeps icons from flipping to the
    /// filled variant on selection.
    private func icon(for section: NavigationState.Section) -> String {
        section.icon
    }
}
