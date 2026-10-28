import SwiftUI
import NavidromeClient

struct PlaylistDetailView: View {
    let playlist: PlaylistSummary
    @Environment(AppState.self) var app

    @State var confirmingDelete = false
    @State var isPreparingPlayback = false

    @State private var displayedCount = 0
    @State private var selection = SongRowSelection()
    @State private var filterText = ""
    @State private var isScrolled = false
    @State private var isSearchExpanded = false
    @State private var showingCommentModal = false
    @State private var commentHovered = false
    private let pageSize = 100

    private struct ScrollOffsetKey: PreferenceKey {
        static let defaultValue: CGFloat = 24
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }

    private var state: PlaylistLoadState? { app.playlistLoadState(for: playlist) }
    var rows: [SubsonicSong] { state?.songs ?? [] }
    var loading: Bool { state?.isLoading ?? true }
    var isSyncing: Bool { state?.isSyncing ?? false }
    private var loadError: String? { state?.error }
    private var filteredRows: [SubsonicSong] {
        guard !filterText.isEmpty else { return rows }
        let query = filterText.localizedLowercase
        return rows.filter {
            $0.displayTitle.localizedLowercase.contains(query) ||
            ($0.artist?.localizedLowercase.contains(query) ?? false) ||
            ($0.album?.localizedLowercase.contains(query) ?? false)
        }
    }
    private var displayedSongs: [SubsonicSong] { Array(filteredRows.prefix(displayedCount)) }

    private var canEditTracks: Bool {
        (currentDetail.isReadonly ?? false) == false
    }

    private var topBar: some View {
        let barOpaque = isScrolled || isSearchExpanded || !filterText.isEmpty
        return LibraryHeader(
            title: isScrolled ? currentDetail.displayName : "",
            searchText: $filterText,
            isLoading: isScrolled && isSyncing,
            filteredCount: filterText.isEmpty ? nil : filteredRows.count,
            totalCount: filterText.isEmpty ? nil : rows.count,
            isSearchExpanded: $isSearchExpanded
        )
        .padding(.horizontal, 20)
        .background {
            if barOpaque {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(alignment: .bottom) {
                        Divider().opacity(0.35)
                    }
                    .transition(.opacity)
            }
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: ScrollOffsetKey.self,
                            value: proxy.frame(in: .named("playlistScrollSpace")).minY
                        )
                    }
                    .frame(height: 0)

                    header(currentDetail)
                        .padding(.bottom, 28)
                    if let loadError, !rows.isEmpty {
                        inlineErrorNotice(loadError)
                            .padding(.bottom, 16)
                    }

                    if displayedSongs.isEmpty && loading {
                        SkeletonSongList(count: 10, showAlbum: true)
                            .padding(.leading, -22)
                            .padding(.trailing, 26)
                    } else if displayedSongs.isEmpty, let loadError {
                        DetailUnavailableView(message: loadError) {
                            app.loadPlaylistIfNeeded(currentDetail.summary, forceReload: true)
                        }
                    } else if filteredRows.isEmpty && !displayedSongs.isEmpty {
                        ContentUnavailableView(
                            "Nothing Found".localized,
                            systemImage: "magnifyingglass",
                            description: Text("Try changing your query.".localized)
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                    } else {
                        ForEach(identifiedSongs) { item in
                            SongRow(
                                song: item.song,
                                index: item.displayIndex,
                                showAlbum: true,
                                isCurrentOverride: currentSongID == item.song.id,
                                playlist: currentDetail.summary,
                                playlistIndex: item.playlistIndex,
                                onPlay: { rowIndex in
                                    app.play(filteredRows, at: rowIndex, context: .playlist(playlist))
                                },
                                isSelected: selection.isSelected(item.song.id),
                                resolveSelection: { selection.selectedSongs(from: filteredRows) },
                                onSelect: { selection.toggle(item.song.id, allSongs: filteredRows) }
                            )
                            .equatable()
                            .padding(.leading, -22)
                            .padding(.trailing, 26)
                        }
                        if displayedCount < filteredRows.count {
                            Color.clear.frame(height: 80)
                                .id("sentinel_\(displayedCount)")
                                .onAppear {
                                    displayedCount = min(displayedCount + pageSize, filteredRows.count)
                                }
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
            }
            .coordinateSpace(name: "playlistScrollSpace")
            .onPreferenceChange(ScrollOffsetKey.self) { minY in
                let scrolled = minY < 5
                if scrolled != isScrolled {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isScrolled = scrolled
                    }
                }
            }

            topBar
                .zIndex(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .refreshable {
            await app.reloadPlaylist(playlist)
        }
        .task(id: playlist.id) {
            displayedCount = 0
            app.loadPlaylistIfNeeded(playlist)
            displayedCount = min(rows.count, pageSize)
        }
        .id(playlist.id)
        .onDisappear {
            app.cancelPlaylistTask(for: playlist.id)
        }
        .onChange(of: rows.count) { _, count in
            if displayedCount < pageSize, count > 0 {
                displayedCount = min(count, pageSize)
            } else if displayedCount > count {
                displayedCount = count
            }
        }
        .onChange(of: filterText) { _, _ in
            displayedCount = min(filteredRows.count, pageSize)
        }
        .confirmationDialog(
            L10n.format("format.playlist.delete.confirmation", playlist.displayName),
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete".localized, role: .destructive) {
                delete(currentDetail)
            }
            Button("Cancel".localized, role: .cancel) {}
        }
        .inWindowModal(isPresented: $showingCommentModal) {
            PlaylistCommentModal(
                title: currentDetail.displayName,
                comment: currentDetail.comment ?? "",
                onDismiss: { showingCommentModal = false }
            )
        }
    }

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
        let trimmedComment = detail.comment?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasComment = !trimmedComment.isEmpty

        return HStack(alignment: .top, spacing: 24) {
            QuickLookCover(coverArt: detail.coverArt, title: detail.displayName)
                .frame(width: 220, height: 220)
                .help("Quick Look artwork".localized)
                .accessibilityLabel("Artwork Preview".localized)
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(detail.displayName)
                            .font(.largeTitle.weight(.semibold))
                        kindLine(detail)
                        if detail.isSmart {
                            editRulesButton(detail)
                        }
                        metaRow(detail)
                    }
                    if hasComment {
                        commentButton(title: detail.displayName, comment: trimmedComment)
                    }
                }
                .offset(y: -6)
                Spacer(minLength: 0)
                actionRow(detail)
            }
            .frame(minHeight: 220)
            Spacer()
        }
    }

    private func editRulesButton(_ detail: PlaylistDetail) -> some View {
        EditRulesButton {
            app.openSmartPlaylistEditor(server: ServerSmartPlaylist(summary: detail.summary))
        }
    }

    private func commentButton(title: String, comment: String) -> some View {
        Button {
            showingCommentModal = true
        } label: {
            Text(comment)
                .font(.callout)
                .foregroundStyle(commentHovered ? Color.primary : AMColor.secondaryText)
                .lineLimit(3)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { commentHovered = $0 }
        .help("Show full description".localized)
    }

    var playableSongs: [SubsonicSong] {
        if app.isOfflineSession {
            return rows.filter { app.isCached($0) }
        }
        return rows
    }

}

// MARK: - Playlist Song List Section

extension PlaylistDetailView {
    private struct IdentifiedSong: Identifiable {
        let displayIndex: Int
        let playlistIndex: Int
        let song: SubsonicSong
        let id: String
    }

    private var identifiedSongs: [IdentifiedSong] {
        var counts: [String: Int] = [:]
        let query = filterText.localizedLowercase
        var result: [IdentifiedSong] = []
        var displayIdx = 0

        for (playlistIdx, song) in rows.enumerated() {
            if !query.isEmpty {
                let matches = song.displayTitle.localizedLowercase.contains(query) ||
                    (song.artist?.localizedLowercase.contains(query) ?? false) ||
                    (song.album?.localizedLowercase.contains(query) ?? false)
                guard matches else { continue }
            }

            guard displayIdx < displayedCount else { break }

            let occ = counts[song.id, default: 0]
            counts[song.id] = occ + 1
            let id = occ == 0 ? song.id : "\(song.id)_\(occ)"

            result.append(IdentifiedSong(
                displayIndex: displayIdx,
                playlistIndex: playlistIdx,
                song: song,
                id: id
            ))
            displayIdx += 1
        }
        return result
    }

    private var currentSongID: String? {
        app.player.currentSong?.id
    }
}
