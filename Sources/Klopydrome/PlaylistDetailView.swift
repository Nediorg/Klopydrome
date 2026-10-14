import SwiftUI
import NavidromeClient

struct PlaylistDetailView: View {
    let playlist: PlaylistSummary
    @Environment(AppState.self) var app

    @State var confirmingDelete = false
    @State var isPreparingPlayback = false

    /// The shared loader retains every song for Player, but SwiftUI only builds a
    /// bounded prefix. A large playlist can therefore begin playing without its
    /// entire list becoming a layout cost on the main actor.
    @State private var displayedCount = 0
    @State private var selection = SongRowSelection()
    @State private var filterText = ""
    @State private var isScrolled = false
    @State private var isSearchExpanded = false
    @State private var showingCommentModal = false
    @State private var commentHovered = false
    @State private var editRulesHovered = false
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

    /// Whether the current user may edit the playlist's tracks (remove rows).
    /// Server-side smart playlists (and shared ones) are readonly.
    private var canEditTracks: Bool {
        (currentDetail.isReadonly ?? false) == false
    }

    private var topBar: some View {
        let barOpaque = isScrolled || isSearchExpanded || !filterText.isEmpty
        return LibraryHeader(
            title: isScrolled ? currentDetail.displayName : "",
            searchText: $filterText,
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
                    PlaylistSongListSection(
                        detail: currentDetail,
                        displayedSongs: displayedSongs,
                        filteredRows: filteredRows,
                        playableSongs: playableSongs,
                        loading: loading,
                        loadError: loadError,
                        canEditTracks: canEditTracks,
                        displayedCount: $displayedCount,
                        pageSize: pageSize,
                        selection: $selection,
                        app: app,
                        onRemove: { index in remove(at: index, from: currentDetail) }
                    )
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
        .onChange(of: rows.count) { _, count in
            if displayedCount == 0, count > 0 {
                displayedCount = min(count, pageSize)
            } else if displayedCount > 0, displayedCount < count {
                // Rows are still streaming in; grow the window so songs that
                // arrived after the first page are visible without a scroll.
                displayedCount = min(displayedCount + pageSize, count)
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
            Button("Удалить", role: .destructive) {
                delete(currentDetail)
            }
            Button("Отмена", role: .cancel) {}
        }
        .inWindowModal(isPresented: $showingCommentModal) {
            PlaylistCommentModal(
                title: currentDetail.displayName,
                comment: currentDetail.comment ?? "",
                onDismiss: { showingCommentModal = false }
            )
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
        let trimmedComment = detail.comment?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasComment = !trimmedComment.isEmpty

        return HStack(alignment: .top, spacing: 24) {
            QuickLookCover(coverArt: detail.coverArt, title: detail.displayName)
                .frame(width: 220, height: 220)
                .help("Быстрый просмотр обложки".localized)
                .accessibilityLabel("Предпросмотр обложки".localized)
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(detail.displayName)
                            .font(.largeTitle.bold())
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
        Button {
            app.openSmartPlaylistEditor(server: ServerSmartPlaylist(summary: detail.summary))
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
        .help("Показать описание полностью".localized)
    }

    var playableSongs: [SubsonicSong] {
        if app.isOfflineSession {
            return rows.filter { app.isCached($0) }
        }
        return rows
    }

}

// MARK: - Playlist Song List Section

private struct PlaylistSongListSection: View {
    let detail: PlaylistDetail
    let displayedSongs: [SubsonicSong]
    let filteredRows: [SubsonicSong]
    let playableSongs: [SubsonicSong]
    let loading: Bool
    let loadError: String?
    let canEditTracks: Bool
    @Binding var displayedCount: Int
    let pageSize: Int
    @Binding var selection: SongRowSelection
    let app: AppState
    let onRemove: (Int) -> Void

    private struct IdentifiedSong: Identifiable {
        let index: Int
        let song: SubsonicSong
        let id: String
    }

    private var identifiedSongs: [IdentifiedSong] {
        var counts: [String: Int] = [:]
        return displayedSongs.enumerated().map { index, song in
            let occ = counts[song.id, default: 0]
            counts[song.id] = occ + 1
            let id = occ == 0 ? song.id : "\(song.id)_\(occ)"
            return IdentifiedSong(index: index, song: song, id: id)
        }
    }

    var body: some View {
        let currentID = app.player.currentSong?.id
        let allSongs = filteredRows
        if displayedSongs.isEmpty && loading {
            SkeletonSongList(count: 10, showAlbum: true)
        } else if displayedSongs.isEmpty, let loadError {
            DetailUnavailableView(message: loadError) {
                app.loadPlaylistIfNeeded(detail.summary, forceReload: true)
            }
        } else if filteredRows.isEmpty && !displayedSongs.isEmpty {
            ContentUnavailableView(
                "Ничего не найдено".localized,
                systemImage: "magnifyingglass",
                description: Text("Попробуйте изменить запрос.".localized)
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        } else {
            ForEach(identifiedSongs) { item in
                SongRow(
                    song: item.song,
                    index: item.index,
                    showAlbum: true,
                    isCurrentOverride: currentID == item.song.id,
                    extraActions: rowExtraActions(index: item.index),
                    onPlay: { rowIndex in
                        if app.isOfflineSession {
                            guard rowIndex < displayedSongs.count else { return }
                            let clickedSong = displayedSongs[rowIndex]
                            let playIndex = playableSongs.firstIndex(where: { $0.id == clickedSong.id }) ?? 0
                            app.play(playableSongs, at: playIndex)
                        } else {
                            app.play(filteredRows, at: rowIndex)
                        }
                    },
                    isSelected: selection.isSelected(item.song.id),
                    resolveSelection: { selection.selectedSongs(from: allSongs) },
                    onSelect: { selection.toggle(item.song.id, allSongs: allSongs) }
                )
                .equatable()
            }
            if displayedCount < filteredRows.count {
                Color.clear.frame(height: 80)
                    .onAppear {
                        displayedCount = min(displayedCount + pageSize, filteredRows.count)
                    }
            }
        }
    }

    private func rowExtraActions(index: Int) -> [SongMenuExtraAction] {
        guard canEditTracks else { return [] }
        return [SongMenuExtraAction(
            title: "Убрать из плейлиста".localized,
            systemImage: "trash",
            action: { onRemove(index) }
        )]
    }
}
