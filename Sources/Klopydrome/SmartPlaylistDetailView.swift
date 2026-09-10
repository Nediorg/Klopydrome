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
    @State private var editing = false
    @State private var confirmingDelete = false

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
                    Button("Изменить правила") { editing = true }
                }
            case .loaded:
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        header
                        actionRow
                        songList
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                }
            }
        }
        .task { await load() }
        .sheet(isPresented: $editing) {
            SmartPlaylistEditorView(playlist: playlist)
        }
        .confirmationDialog("Удалить умный плейлист?", isPresented: $confirmingDelete) {
            Button("Удалить", role: .destructive) { delete() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text(L10n.format("format.smartPlaylist.delete.warning", playlist.name))
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 24) {
            Image(systemName: "gearshape")
                .font(.system(size: 72))
                .foregroundStyle(.secondary)
                .frame(width: 220, height: 220)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.gray.opacity(0.15))
                )
            VStack(alignment: .leading, spacing: 10) {
                Text(playlist.name)
                    .font(.largeTitle.bold())
                Text("Умный плейлист".localized)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                if !playlist.ruleSummary.isEmpty {
                    Text(playlist.ruleSummary)
                        .font(.callout)
                        .foregroundStyle(AMColor.secondaryText)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
                actionRow
            }
            .frame(minHeight: 200)
            .padding(.top, 4)
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
                    editing = true
                } onRename: {
                    editing = true
                } onDelete: {
                    confirmingDelete = true
                }
            }
            .help("Действия над плейлистом")
        }
    }

    private var songList: some View {
        let currentID = app.player.currentSong?.id
        return LazyVStack(spacing: 0) {
            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                SongRow(song: song, index: index, showAlbum: true,
                        isCurrentOverride: currentID == song.id,
                        onPlay: { playIndex in app.play(songs, at: playIndex) })
                if index < songs.count - 1 { Divider().opacity(0.3) }
            }
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
