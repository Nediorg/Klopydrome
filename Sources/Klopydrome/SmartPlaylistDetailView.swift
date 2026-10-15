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
    @State private var editRulesHovered = false

    private var songs: [SubsonicSong] {
        if case .loaded(let songs) = state { return songs }
        return []
    }

    var body: some View {
        VStack(spacing: 0) {
            switch state {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Не удалось загрузить", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Повторить") { Task { await load() } }
                }
            case .loaded where songs.isEmpty:
                ContentUnavailableView {
                    Label("Нет совпадений", systemImage: "gearshape")
                } description: {
                    Text("Пока нет песен, подходящих под правила этого умного плейлиста.".localized)
                } actions: {
                    Button("Изменить правила") { app.openSmartPlaylistEditor(playlist: playlist) }
                }
            case .loaded:
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        header
                            .padding(.bottom, 28)
                        songList
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await load() }
        .confirmationDialog("Удалить умный плейлист?", isPresented: $confirmingDelete) {
            Button("Удалить", role: .destructive) { delete() }
            Button("Отмена", role: .cancel) {}
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
                        Text("Умный плейлист".localized)
                            .font(.title2.weight(.regular))
                            .foregroundStyle(.secondary)
                        Button {
                            app.openSmartPlaylistEditor(playlist: playlist)
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "gearshape.fill")
                                    .font(.system(size: 8.5, weight: .semibold))
                                Text("Редактировать правила".localized)
                                    .font(.callout.bold())
                            }
                            .foregroundStyle(AMColor.accent)
                            .brightness(editRulesHovered ? 0.15 : 0)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .onHover { editRulesHovered = $0 }
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
                        .help("Показать описание полностью".localized)
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
            ActionPill(title: "Слушать", systemImage: "play.fill", filled: true) {
                if !songs.isEmpty { app.play(songs, at: 0) }
            }
            ActionPill(title: "Перемешать", systemImage: "shuffle", filled: true) {
                if !songs.isEmpty { app.playShuffled(songs) }
            }
            ActionPill(title: "Обновить", systemImage: "arrow.clockwise", filled: false) {
                Task { await load() }
            }
            .help("Пересчитать подходящие песни на сервере.")
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
            .help("Действия над плейлистом")
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

    @ViewBuilder
    private var songList: some View {
        let currentID = app.player.currentSong?.id
        let allSongs = songs
        ForEach(identifiedSongs) { item in
            SongRow(
                song: item.song,
                index: item.index,
                showAlbum: true,
                isCurrentOverride: currentID == item.song.id,
                onPlay: { playIndex in app.play(songs, at: playIndex) },
                isSelected: selection.isSelected(item.song.id),
                resolveSelection: { selection.selectedSongs(from: allSongs) },
                onSelect: { selection.toggle(item.song.id, allSongs: allSongs) }
            )
            .equatable()
        }
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
