import SwiftUI
import NavidromeClient

struct PlaylistDetailView: View {
    let playlist: PlaylistSummary
    @Environment(AppState.self) private var app

    private enum ActiveEditor: Identifiable {
        case playlist(PlaylistSummary)
        case serverRules(ServerSmartPlaylist)

        var id: String {
            switch self {
            case .playlist(let playlist): return "playlist-\(playlist.id)"
            case .serverRules(let playlist): return "server-rules-\(playlist.id)"
            }
        }
    }

    @State private var activeEditor: ActiveEditor?
    @State private var confirmingDelete = false
    @State private var isPreparingPlayback = false

    /// The shared loader retains every song for Player, but SwiftUI only builds a
    /// bounded prefix. A large playlist can therefore begin playing without its
    /// entire list becoming a layout cost on the main actor.
    @State private var displayedCount = 0
    @State private var selection = SongRowSelection()
    private let pageSize = 100

    private var state: PlaylistLoadState? { app.playlistLoadState(for: playlist) }
    private var rows: [SubsonicSong] { state?.songs ?? [] }
    private var loading: Bool { state?.isLoading ?? true }
    private var loadError: String? { state?.error }
    private var displayedSongs: [SubsonicSong] { Array(rows.prefix(displayedCount)) }

    /// Whether the current user may edit the playlist's tracks (remove rows).
    /// Server-side smart playlists (and shared ones) are readonly.
    private var canEditTracks: Bool {
        (currentDetail.isReadonly ?? false) == false
    }

    var body: some View {
        Group {
            if state?.detail == nil, let loadError, !loading {
                ContentUnavailableView {
                    Label("Плейлист недоступен", systemImage: "music.note.list")
                } description: {
                    Text(loadError)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        header(currentDetail)
                            .padding(.bottom, 28)
                        songList(currentDetail)
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: playlist.id) {
            displayedCount = 0
            app.loadPlaylistIfNeeded(playlist)
            displayedCount = min(rows.count, pageSize)
        }
        .onChange(of: rows.count) { _, count in
            if displayedCount == 0, count > 0 {
                displayedCount = min(count, pageSize)
            } else if displayedCount > 0, displayedCount < count {
                // Rows are still streaming in; grow the window so songs that
                // arrived after the first page are visible without a scroll.
                displayedCount = min(displayedCount + pageSize, count)
            }
        }
        .sheet(item: $activeEditor) { editor in
            switch editor {
            case .playlist(let summary):
                CreatePlaylistModal(songs: [], existing: summary) {
                    app.invalidatePlaylistDetail(for: playlist.id)
                    app.loadPlaylistIfNeeded(playlist, forceReload: true)
                }
            case .serverRules(let server):
                SmartPlaylistEditorView(playlist: nil, server: server)
            }
        }
        .confirmationDialog(
            L10n.format("format.playlist.delete.confirmation", playlist.displayName),
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                delete(currentDetail)
            }
            Button("Отмена", role: .cancel) {}
        }
    }

    /// Header data is available immediately from the summary that opened this
    /// destination. The shared loader fills richer metadata and rows afterward.
    private var currentDetail: PlaylistDetail {
        state?.detail ?? PlaylistDetail(
            id: playlist.id,
            name: playlist.name,
            comment: playlist.comment,
            owner: playlist.owner,
            coverArt: playlist.coverArt,
            songCount: playlist.songCount,
            duration: playlist.duration,
            created: playlist.created,
            changed: playlist.changed,
            isPublic: playlist.isPublic,
            isReadonly: playlist.isReadonly,
            validUntil: playlist.validUntil
        )
    }

    private func header(_ detail: PlaylistDetail) -> some View {
        HStack(alignment: .top, spacing: 24) {
            QuickLookCover(coverArt: detail.coverArt, title: detail.displayName)
                .frame(width: 220, height: 220)
                .help("Быстрый просмотр обложки".localized)
                .accessibilityLabel("Предпросмотр обложки".localized)
            VStack(alignment: .leading, spacing: 10) {
                Text(detail.displayName)
                    .font(.largeTitle.bold())
                kindLine(detail)
                if let comment = detail.comment, !comment.isEmpty {
                    Text(comment)
                        .font(.callout)
                        .foregroundStyle(AMColor.secondaryText)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                metaRow(detail)
                Spacer(minLength: 0)
                actionRow(detail)
            }
            .frame(minHeight: 200)
            .padding(.top, 4)
            Spacer()
        }
    }

    private func kindLine(_ detail: PlaylistDetail) -> some View {
        var parts: [String] = []
        parts.append(detail.isSmart ? "Умный плейлист".localized : "Плейлист".localized)
        if detail.isPublic == true { parts.append("Открытый".localized) }
        return Text(parts.joined(separator: " · "))
            .font(.title3.weight(.medium))
            .foregroundStyle(.secondary)
    }

    private func metaRow(_ detail: PlaylistDetail) -> some View {
        var parts: [String] = []
        let count = detail.songCount ?? rows.count
        parts.append("\(count) \(Pluralized.song(count))")
        if let duration = detail.duration {
            parts.append(Player.format(seconds: Double(duration)))
        }
        return Text(parts.joined(separator: " · "))
            .font(.callout)
            .foregroundStyle(AMColor.secondaryText)
    }

    private var playableSongs: [SubsonicSong] {
        if app.isOfflineSession {
            return rows.filter { app.isCached($0) }
        }
        return rows
    }

    private func actionRow(_ detail: PlaylistDetail) -> some View {
        HStack(spacing: 10) {
            ActionPill(
                title: "Слушать",
                systemImage: "play.fill",
                filled: true
            ) {
                Task { await startPlayback(shuffled: false) }
            }
            .disabled(isPreparingPlayback || (app.isOfflineSession && playableSongs.isEmpty))

            ActionPill(
                title: "Перемешать",
                systemImage: "shuffle",
                filled: true
            ) {
                Task { await startPlayback(shuffled: true) }
            }
            .disabled(isPreparingPlayback || (app.isOfflineSession && playableSongs.isEmpty))

            Spacer()
            HStack(spacing: 8) {
                RoundFavoriteButton(isStarred: app.isFollowed(detail.summary)) {
                    app.toggleFollow(detail.summary)
                }
                RoundEllipsisMenu {
                    PlaylistContextMenuItems(
                        playlist: detail.summary,
                        onRename: { activeEditor = .playlist(detail.summary) },
                        onEditRules: {
                            guard detail.isSmart else { return }
                            activeEditor = .serverRules(ServerSmartPlaylist(summary: detail.summary))
                        },
                        onDelete: { confirmingDelete = true }
                    )
                }
                .help("Действия над плейлистом".localized)
            }
        }
    }

    @ViewBuilder
    private func songList(_ detail: PlaylistDetail) -> some View {
        let currentID = app.player.currentSong?.id
        let allSongs = rows
        if rows.isEmpty && loading {
            skeletonRows
        } else {
            ForEach(Array(displayedSongs.enumerated()), id: \.offset) { index, song in
                SongRow(
                    song: song,
                    index: index,
                    showAlbum: true,
                    isCurrentOverride: currentID == song.id,
                    extraMenuItems: canEditTracks
                        ? { AnyView(Button("Убрать из плейлиста".localized) { remove(at: index, from: detail) }) }
                        : nil,
                    onPlay: { rowIndex in
                        if app.isOfflineSession {
                            let playable = playableSongs
                            guard rowIndex < displayedSongs.count else { return }
                            let clickedSong = displayedSongs[rowIndex]
                            let playIndex = playable.firstIndex(where: { $0.id == clickedSong.id }) ?? 0
                            app.play(playable, at: playIndex)
                        } else {
                            app.play(rows, at: rowIndex)
                        }
                    },
                    isSelected: selection.isSelected(song.id),
                    resolveSelection: { selection.selectedSongs(from: allSongs) },
                    onSelect: { selection.toggle(song.id, allSongs: allSongs) }
                )
                .equatable()
            }
            // Sentinel: appears when the user scrolls near the bottom of the
            // current page window. Grows the window by one page.
            if displayedCount < rows.count {
                Color.clear.frame(height: 80)
                    .onAppear {
                        displayedCount = min(displayedCount + pageSize, rows.count)
                    }
            }
        }
    }

    /// Placeholder song rows shown while the playlist's songs stream in.
    private var skeletonRows: some View {
        ForEach(0..<12, id: \.self) { _ in
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 180, height: 12)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.05))
                        .frame(width: 120, height: 10)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            Divider().opacity(0.3)
        }
    }

    private func startPlayback(shuffled: Bool) async {
        isPreparingPlayback = true
        defer { isPreparingPlayback = false }
        if shuffled {
            await app.playShuffled(playlist)
        } else {
            await app.play(playlist)
        }
    }

    private func remove(at index: Int, from detail: PlaylistDetail) {
        guard let client = app.client else { return }
        Task {
            try? await client.updatePlaylist(id: detail.id, removeIndexes: [index])
            app.invalidatePlaylistDetail(for: detail.id)
            app.loadPlaylistIfNeeded(playlist, forceReload: true)
        }
    }

    private func delete(_ detail: PlaylistDetail) {
        guard let client = app.client else { return }
        Task {
            try? await client.deletePlaylist(id: detail.id)
            app.invalidatePlaylistDetail(for: detail.id)
            await app.refreshPlaylists()
        }
    }
}
