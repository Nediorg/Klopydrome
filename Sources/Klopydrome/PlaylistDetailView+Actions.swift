import SwiftUI
import NavidromeClient

// MARK: - PlaylistDetailView Error & Action Helpers

extension PlaylistDetailView {
    func emptyErrorState(_ error: String) -> some View {
        ContentUnavailableView {
            Label("Не удалось загрузить треки".localized, systemImage: "exclamationmark.triangle")
        } description: {
            Text(error)
        } actions: {
            Button("Повторить".localized) {
                app.loadPlaylistIfNeeded(playlist, forceReload: true)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .padding(.bottom, 60)
    }

    func inlineErrorNotice(_ error: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
            Text(error)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            Button("Повторить".localized) {
                app.loadPlaylistIfNeeded(playlist, forceReload: true)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    func startPlayback(shuffled: Bool) async {
        isPreparingPlayback = true
        defer { isPreparingPlayback = false }
        if shuffled {
            await app.playShuffled(playlist)
        } else {
            await app.play(playlist)
        }
    }

    func remove(at index: Int, from detail: PlaylistDetail) {
        guard app.confirmOfflineAction() else { return }
        guard let client = app.client else { return }
        Task {
            try? await client.updatePlaylist(id: detail.id, removeIndexes: [index])
            app.invalidatePlaylistDetail(for: detail.id)
            app.loadPlaylistIfNeeded(playlist, forceReload: true)
        }
    }

    func delete(_ detail: PlaylistDetail) {
        guard app.confirmOfflineAction() else { return }
        guard let client = app.client else { return }
        Task {
            try? await client.deletePlaylist(id: detail.id)
            app.invalidatePlaylistDetail(for: detail.id)
            await app.refreshPlaylists()
        }
    }

    func kindLine(_ detail: PlaylistDetail) -> some View {
        var parts: [String] = []
        parts.append(detail.isSmart ? "Умный плейлист".localized : "Плейлист".localized)
        if detail.isPublic == true { parts.append("Открытый".localized) }
        return Text(parts.joined(separator: " · "))
            .font(.title3.weight(.medium))
            .foregroundStyle(.secondary)
    }

    func metaRow(_ detail: PlaylistDetail) -> some View {
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

    func actionRow(_ detail: PlaylistDetail) -> some View {
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
                if loading {
                    ProgressView()
                        .controlSize(.small)
                        .help("Синхронизация с сервером…".localized)
                        .transition(.opacity)
                }
                RoundFavoriteButton(isStarred: app.isFollowed(detail.summary)) {
                    app.toggleFollow(detail.summary)
                }
                RoundEllipsisMenu {
                    PlaylistContextMenuItems(
                        playlist: detail.summary,
                        onRename: {
                            app.openCreatePlaylist(existing: detail.summary) {
                                app.invalidatePlaylistDetail(for: playlist.id)
                                app.loadPlaylistIfNeeded(playlist, forceReload: true)
                            }
                        },
                        onEditRules: {
                            guard detail.isSmart else { return }
                            app.openSmartPlaylistEditor(server: ServerSmartPlaylist(summary: detail.summary))
                        },
                        onDelete: { confirmingDelete = true }
                    )
                }
                .help("Действия над плейлистом".localized)
            }
            .animation(.easeInOut(duration: 0.2), value: loading)
        }
    }

    /// Placeholder song rows shown while the playlist's songs stream in.
    /// Matches the exact layout, margins, and row height (46pt) of `SongRow(showAlbum: true)`.
    var skeletonRows: some View {
        SkeletonSongList(count: 10, showAlbum: true)
    }
}
