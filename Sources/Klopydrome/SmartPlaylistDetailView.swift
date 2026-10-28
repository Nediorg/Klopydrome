import SwiftUI
import NavidromeClient

struct SmartPlaylistDetailView: View {
    let playlist: SmartPlaylist
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    private enum LoadState {
        case loading
        case loaded([SubsonicSong])
        case failed(String)
    }

    @State private var state: LoadState = .loading
    @State private var confirmingDelete = false
    @State private var selection = SongRowSelection()
    @State private var showingCommentModal = false
    @State private var summaryHovered = false

    private var songs: [SubsonicSong] {
        if case .loaded(let songs) = state { return songs }
        return []
    }

    var body: some View {
        VStack(spacing: 0) {
            switch state {
            case .loading:
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        header
                            .padding(.bottom, 28)
                        SkeletonSongList(count: 10, showAlbum: true)
                            .padding(.leading, -22)
                            .padding(.trailing, 26)
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                }
            case .failed(let message):
                ContentUnavailableView {
                    Label("Failed to load".localized, systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Retry".localized) { Task { await load() } }
                }
            case .loaded where songs.isEmpty:
                ContentUnavailableView {
                    Label("No Matches".localized, systemImage: "gearshape")
                } description: {
                    Text("There are no songs matching the rules for this smart playlist yet.".localized)
                } actions: {
                    Button("Edit Rules".localized) { app.openSmartPlaylistEditor(playlist: playlist) }
                }
            case .loaded:
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        header
                            .padding(.bottom, 28)
                        ForEach(identifiedSongs) { item in
                            SongRow(
                                song: item.song,
                                index: item.index,
                                showAlbum: true,
                                isCurrentOverride: currentSongID == item.song.id,
                                onPlay: { playIndex in
                                    app.play(songs, at: playIndex, context: .smartPlaylist(playlist))
                                },
                                isSelected: selection.isSelected(item.song.id),
                                resolveSelection: { selection.selectedSongs(from: songs) },
                                onSelect: { selection.toggle(item.song.id, allSongs: songs) }
                            )
                            .equatable()
                            .padding(.leading, -22)
                            .padding(.trailing, 26)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await load() }
        .confirmationDialog("Delete Smart Playlist?".localized, isPresented: $confirmingDelete) {
            Button("Delete".localized, role: .destructive) { delete() }
            Button("Cancel".localized, role: .cancel) {}
        } message: {
            Text(L10n.format("format.smartPlaylist.delete.warning", playlist.name))
        }
        .inWindowModal(isPresented: $showingCommentModal) {
            PlaylistCommentModal(
                title: playlist.name,
                comment: playlist.ruleSummary,
                onDismiss: { showingCommentModal = false }
            )
        }
    }

    private var header: some View {
        let hasSummary = !playlist.ruleSummary.isEmpty
        return HStack(alignment: .top, spacing: 24) {
            Image(systemName: "gearshape")
                .font(.system(size: 72))
                .foregroundStyle(.secondary)
                .frame(width: 220, height: 220)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.gray.opacity(0.15))
                )
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(playlist.name)
                            .font(.largeTitle.weight(.semibold))
                        Text("Smart Playlist".localized)
                            .font(.title2.weight(.regular))
                            .foregroundStyle(.secondary)
                        EditRulesButton {
                            app.openSmartPlaylistEditor(playlist: playlist)
                        }
                    }
                    if hasSummary {
                        Button {
                            showingCommentModal = true
                        } label: {
                            Text(playlist.ruleSummary)
                                .font(.callout)
                                .foregroundStyle(summaryHovered ? Color.primary : AMColor.secondaryText)
                                .lineLimit(3)
                                .truncationMode(.tail)
                                .multilineTextAlignment(.leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .onHover { summaryHovered = $0 }
                        .help("Show full description".localized)
                    }
                }
                .offset(y: -6)
                Spacer(minLength: 0)
                actionRow
            }
            .frame(minHeight: 220)
            Spacer()
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            ActionPill(title: "Play".localized, systemImage: "play.fill", filled: true) {
                app.play(songs, at: 0, context: .smartPlaylist(playlist))
            }
            ActionPill(title: "Shuffle".localized, systemImage: "shuffle", filled: true) {
                app.playShuffled(songs, context: .smartPlaylist(playlist))
            }
            ActionPill(title: "Refresh".localized, systemImage: "arrow.clockwise", filled: false) {
                Task { await load() }
            }
            .help("Recalculate matching songs on server.".localized)
            Spacer()
            RoundEllipsisMenu {
                SmartPlaylistContextMenuItems(playlist: playlist) {
                    app.openSmartPlaylistEditor(playlist: playlist)
                } onRename: {
                    app.openSmartPlaylistEditor(playlist: playlist)
                } onDelete: {
                    confirmingDelete = true
                }
            }
            .help("Playlist Actions".localized)
        }
    }

    private struct IdentifiedSong: Identifiable {
        let index: Int
        let song: SubsonicSong
        let id: String
    }

    private var identifiedSongs: [IdentifiedSong] {
        var counts: [String: Int] = [:]
        return songs.enumerated().map { index, song in
            let occ = counts[song.id, default: 0]
            counts[song.id] = occ + 1
            let id = occ == 0 ? song.id : "\(song.id)_\(occ)"
            return IdentifiedSong(index: index, song: song, id: id)
        }
    }

    private var currentSongID: String? {
        app.player.currentSong?.id
    }

    private func load() async {
        state = .loading
        do {
            let songs = try await app.computeSmartPlaylist(playlist)
            state = .loaded(songs)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func delete() {
        app.deleteSmartPlaylist(id: playlist.id)
        dismiss()
    }
}
