import SwiftUI
import NavidromeClient

struct SidebarView: View {
    @Environment(AppState.self) private var app

    enum Selection: Hashable {
        case section(NavigationState.Section)
        case playlistID(String)
    }

    @State private var confirmingDeleteID: String?

    private var currentSelection: Selection {
        if let playlist = app.nav.selectedPlaylist {
            return .playlistID(playlist.id)
        }
        return .section(app.nav.selected)
    }

    private var selectionBinding: Binding<Selection?> {
        Binding(
            get: { currentSelection },
            set: { newValue in
                guard let newValue else { return }
                select(newValue)
            }
        )
    }

    private var playlists: [PlaylistSummary] { app.library.playlists }

    var body: some View {
        List(selection: selectionBinding) {
            Section {
                sidebarRow("Home".localized, .home)
            }

            SidebarLibrarySection(selection: currentSelection, select: select)

            Section {
                Button {
                    select(.section(.playlists))
                } label: {
                    playlistRow("All Playlists".localized,
                                icon: icon(for: .playlists),
                                isSelected: currentSelection == .section(.playlists))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .tag(Selection.section(.playlists))
                .contextMenu { playlistContextMenu }

                ForEach(personalPlaylists) { playlist in
                    Button {
                        select(.playlistID(playlist.id))
                    } label: {
                        playlistRow(playlist.displayName,
                                    icon: playlist.isSmart ? "gearshape" : "music.note.list",
                                    isSelected: currentSelection == .playlistID(playlist.id))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .tag(Selection.playlistID(playlist.id))
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
                Text("Playlists".localized)
                    .contextMenu { playlistContextMenu }
            }

            if !sharedPlaylists.isEmpty {
                Section {
                    ForEach(sharedPlaylists) { playlist in
                        Button {
                            select(.playlistID(playlist.id))
                        } label: {
                            playlistRow(playlist.displayName,
                                        icon: "arrow.turn.down.right",
                                        isSelected: currentSelection == .playlistID(playlist.id))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .tag(Selection.playlistID(playlist.id))
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
                    Text("Shared Playlists".localized)
                        .contextMenu { playlistContextMenu }
                }
            }
        }
        .listStyle(.sidebar)
        .contentMargins(.top, LayoutMetrics.trafficLightInset, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarStatusCard()
        }
        .background(.thinMaterial, ignoresSafeAreaEdges: .all)
        .navigationSplitViewColumnWidth(
            min: LayoutMetrics.sidebarIdealWidth,
            ideal: LayoutMetrics.sidebarIdealWidth,
            max: LayoutMetrics.sidebarMaxWidth
        )
        .frame(minWidth: LayoutMetrics.sidebarIdealWidth, alignment: .leading)
        .clipped()
        .confirmationDialog(
            "Delete Playlist?".localized,
            isPresented: Binding(
                get: { confirmingDeleteID != nil },
                set: { if !$0 { confirmingDeleteID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete".localized, role: .destructive) {
                if let id = confirmingDeleteID,
                   let playlist = playlists.first(where: { $0.id == id }) {
                    Task { await app.deletePlaylist(playlist) }
                }
                confirmingDeleteID = nil
            }
            Button("Cancel".localized, role: .cancel) { confirmingDeleteID = nil }
        }
        .searchable(text: Bindable(app).nav.searchQuery, placement: .sidebar, prompt: Text("Search".localized))
        .submitLabel(.search)
        .onSubmit(of: .search) { submitSearch() }
        .task(id: app.isConnected) { await loadPlaylists() }
    }

    private func select(_ newValue: Selection) {
        applySelection(newValue)
        app.nav.history.removeAll()
        app.nav.navVersion += 1
    }

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
                app.openCreatePlaylist()
            } label: {
                Label("New Playlist".localized, systemImage: "plus")
            }
            Button {
                app.openSmartPlaylistEditor()
            } label: {
                Label("New Smart Playlist".localized, systemImage: "gearshape")
            }
        }
    }

    private func beginRename(_ playlist: PlaylistSummary) {
        app.openCreatePlaylist(existing: playlist)
    }

    private func editRules(_ playlist: PlaylistSummary) {
        guard playlist.isSmart else { return }
        app.openSmartPlaylistEditor(server: ServerSmartPlaylist(summary: playlist))
    }

    private var username: String {
        app.effectiveUsername
    }

    private var personalPlaylists: [PlaylistSummary] {
        guard !username.isEmpty else {
            return playlists
        }
        return playlists.filter { playlist in
            guard let owner = playlist.owner?.trimmingCharacters(in: .whitespacesAndNewlines), !owner.isEmpty else {
                return true
            }
            return owner.localizedCaseInsensitiveCompare(username) == .orderedSame
        }
    }

    private var sharedPlaylists: [PlaylistSummary] {
        guard !username.isEmpty else {
            return []
        }
        return playlists.filter { playlist in
            guard let owner = playlist.owner?.trimmingCharacters(in: .whitespacesAndNewlines), !owner.isEmpty else {
                return false
            }
            return owner.localizedCaseInsensitiveCompare(username) != .orderedSame
        }
    }

    private func submitSearch() {
        let query = app.nav.searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        app.nav.selected = .search
        app.nav.selectedPlaylist = nil
        app.nav.history.removeAll()
        app.nav.navVersion += 1
    }

    private func sidebarRow(_ text: String, _ section: NavigationState.Section) -> some View {
        let isSelected = currentSelection == .section(section)
        return Button {
            select(.section(section))
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon(for: section))
                    .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                    .frame(width: 16, height: 16)
                Text(text.localized)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tag(Selection.section(section))
    }

    private func playlistRow(_ text: String, icon: String, isSelected: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(isSelected ? .white : Color(nsColor: .darkGray))
                .frame(width: 16, height: 16)
            Text(text.localized)
        }
    }

    private func icon(for section: NavigationState.Section) -> String {
        section.icon
    }
}
