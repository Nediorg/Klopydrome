import SwiftUI
import NavidromeClient

extension PlaylistDetailView {

    func inlineErrorNotice(_ error: String) -> some View {
        DetailInlineErrorBanner(message: error) {
            app.loadPlaylistIfNeeded(playlist, forceReload: true)
        }
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
        Task {
            await app.removeSongFromPlaylist(playlistID: detail.id, at: index)
        }
    }

    func delete(_ detail: PlaylistDetail) {
        guard app.confirmOfflineAction() else { return }
        Task {
            await app.deletePlaylist(detail.summary)
        }
    }

    func kindLine(_ detail: PlaylistDetail) -> some View {
        var parts: [String] = []
        parts.append(detail.isSmart ? "Smart Playlist".localized : "Playlist".localized)
        if detail.isPublic == true { parts.append("Public".localized) }
        return Text(parts.joined(separator: " · "))
            .font(.title2.weight(.regular))
            .foregroundStyle(.secondary)
    }

    func metaRow(_ detail: PlaylistDetail) -> some View {
        var parts: [String] = []
        let count = detail.songCount ?? rows.count
        parts.append("\(count) \(Pluralized.song(count))")
        if let duration = detail.duration {
            parts.append(Player.format(seconds: Double(duration)))
        }
        return SelectableHeaderText(
            text: parts.joined(separator: " · "),
            font: SelectableHeaderText.font(for: .callout, weight: .bold),
            color: AMColor.secondaryNSColor
        )
    }

    func actionRow(_ detail: PlaylistDetail) -> some View {
        HStack(spacing: 10) {
            ActionPill(
                title: "Play".localized,
                systemImage: "play.fill",
                filled: true
            ) {
                Task { await startPlayback(shuffled: false) }
            }
            .disabled(isPreparingPlayback || (app.isOfflineSession && playableSongs.isEmpty))

            ActionPill(
                title: "Shuffle".localized,
                systemImage: "shuffle",
                filled: true
            ) {
                Task { await startPlayback(shuffled: true) }
            }
            .disabled(isPreparingPlayback || (app.isOfflineSession && playableSongs.isEmpty))

            Spacer()
            HStack(spacing: 8) {
                if isSyncing {
                    ProgressView()
                        .controlSize(.small)
                        .help("Syncing with server…".localized)
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
                .help("Playlist Actions".localized)
            }
            .animation(.easeInOut(duration: 0.2), value: isSyncing)
        }
    }

    var featuredArtists: [PlaylistFeaturedArtist] {
        guard filterText.isEmpty else { return [] }
        var counts: [String: (id: String, name: String, coverArt: String?, count: Int)] = [:]
        for song in rows {
            guard let rawName = song.artist?.trimmingCharacters(in: .whitespacesAndNewlines), !rawName.isEmpty else { continue }
            let key = rawName.lowercased()
            let artistID = song.artistId ?? key
            if let existing = counts[key] {
                counts[key] = (existing.id, existing.name, existing.coverArt ?? song.coverArt, existing.count + 1)
            } else {
                counts[key] = (artistID, rawName, song.coverArt, 1)
            }
        }
        let list = counts.values.map {
            PlaylistFeaturedArtist(id: $0.id, name: $0.name, coverArt: $0.coverArt, trackCount: $0.count)
        }
        return list.sorted {
            if $0.trackCount != $1.trackCount {
                return $0.trackCount > $1.trackCount
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var featuredArtistsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Featured Artists".localized)
                .font(.title3.weight(.bold))

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 20) {
                    ForEach(featuredArtists.prefix(20)) { featured in
                        ArtistTile(
                            artist: Artist(id: featured.id, name: featured.name, coverArt: featured.coverArt),
                            size: 88,
                            coverArt: featured.coverArt
                        )
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(.top, 24)
        .padding(.bottom, 16)
    }

    func handlePlaylistReorder(_ payload: TrackDragPayload, toIndex: Int) {
        guard case .playlistTrack(let pID, let fromIndex, _) = payload.kind,
              pID == currentDetail.id,
              fromIndex != toIndex else { return }

        guard var currentState = app.playlistLoadStates[currentDetail.id] else { return }
        let originalSongs = currentState.songs
        guard fromIndex >= 0 && fromIndex < originalSongs.count else { return }

        var updatedSongs = originalSongs
        let song = updatedSongs.remove(at: fromIndex)
        let destination = min(max(toIndex, 0), updatedSongs.count)
        updatedSongs.insert(song, at: destination)
        currentState.songs = updatedSongs
        app.playlistLoadStates[currentDetail.id] = currentState

        Task {
            do {
                try await app.movePlaylistTrack(playlistId: currentDetail.id, fromIndex: fromIndex, toIndex: toIndex)
            } catch {
                if var revertState = app.playlistLoadStates[currentDetail.id] {
                    revertState.songs = originalSongs
                    app.playlistLoadStates[currentDetail.id] = revertState
                }
            }
        }
    }
}

struct PlaylistRowReorderModifier: ViewModifier {
    let isEnabled: Bool
    let playlistIndex: Int
    let dropTargetIndex: Int?
    let onDrop: (TrackDragPayload) -> Void
    let onTargetChange: (Bool) -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .dropDestination(for: TrackDragPayload.self) { items, _ in
                    guard let payload = items.first else { return false }
                    onDrop(payload)
                    return true
                } isTargeted: { targeted in
                    onTargetChange(targeted)
                }
                .overlay(alignment: .top) {
                    if dropTargetIndex == playlistIndex {
                        Rectangle()
                            .fill(AMColor.accent)
                            .frame(height: 2)
                            .padding(.horizontal, 4)
                    }
                }
        } else {
            content
        }
    }
}
