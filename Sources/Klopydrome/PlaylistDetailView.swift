import SwiftUI
import NavidromeClient

struct PlaylistDetailView: View {
    let playlist: PlaylistSummary
    @Environment(AppState.self) var app

    @State var confirmingDelete = false
    @State var isPreparingPlayback = false

    @State private var displayedCount = 0
    @State private var selection = SongRowSelection()
    @State var filterText = ""
    @State private var isScrolled = false
    @State private var isSearchExpanded = false
    @State private var showingCommentModal = false
    @State private var commentHovered = false
    @State var sortOption: PlaylistTrackSort = .playlistOrder
    @State var sortAscending: Bool = true
    @State var dropTargetPlaylistIndex: Int?
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
    var loadError: String? { state?.error }
    var filteredRows: [SubsonicSong] { filteredIndexedRows.map(\.song) }
    var displayedSongs: [SubsonicSong] { Array(filteredRows.prefix(displayedCount)) }

    private var topBar: some View {
        let barOpaque = isScrolled || isSearchExpanded || !filterText.isEmpty
        return LibraryHeader(
            title: isScrolled ? currentDetail.displayName : "",
            searchText: $filterText,
            isLoading: isScrolled && isSyncing,
            filteredCount: filterText.isEmpty ? nil : filteredIndexedRows.count,
            totalCount: filterText.isEmpty ? nil : rows.count,
            isSearchExpanded: $isSearchExpanded
        ) {
            Picker("Sort".localized, selection: $sortOption) {
                ForEach(PlaylistTrackSort.allCases) { option in
                    Text(option.label.localized).tag(option)
                }
            }
            .pickerStyle(.inline)

            Divider()

            Picker("Order".localized, selection: $sortAscending) {
                Text("Ascending".localized).tag(true)
                Text("Descending".localized).tag(false)
            }
            .pickerStyle(.inline)
        }
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
                    } else if filteredRows.isEmpty && !filterText.isEmpty {
                        ContentUnavailableView(
                            "Nothing Found".localized,
                            systemImage: "magnifyingglass",
                            description: Text("Try changing your query.".localized)
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                    } else if rows.isEmpty {
                        if currentDetail.isSmart {
                            ContentUnavailableView {
                                Label("No Matches".localized, systemImage: "gearshape")
                            } description: {
                                Text("There are no songs matching the rules for this smart playlist yet.".localized)
                            } actions: {
                                Button("Edit Rules".localized) {
                                    app.openSmartPlaylistEditor(server: ServerSmartPlaylist(summary: currentDetail.summary))
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                        } else {
                            ContentUnavailableView(
                                "No Playlists".localized,
                                systemImage: "music.note.list",
                                description: Text("Create a playlist to group your music.".localized)
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                        }
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
                            .modifier(PlaylistRowReorderModifier(
                                isEnabled: isReorderingEnabled,
                                playlistIndex: item.playlistIndex,
                                dropTargetIndex: dropTargetPlaylistIndex,
                                onDrop: { payload in
                                    handlePlaylistReorder(payload, toIndex: item.playlistIndex)
                                },
                                onTargetChange: { targeted in
                                    if targeted {
                                        dropTargetPlaylistIndex = item.playlistIndex
                                    } else if dropTargetPlaylistIndex == item.playlistIndex {
                                        dropTargetPlaylistIndex = nil
                                    }
                                }
                            ))
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
                        if filterText.isEmpty && featuredArtists.count >= 2 {
                            featuredArtistsSection
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
}

// MARK: - Header & Metadata

extension PlaylistDetailView {
    var sortedIndexedRows: [(playlistIndex: Int, song: SubsonicSong)] {
        let base = rows.enumerated().map { (playlistIndex: $0.offset, song: $0.element) }
        guard sortOption != .playlistOrder else {
            return sortAscending ? base : base.reversed()
        }

        return base.sorted { lhs, rhs in
            let result: ComparisonResult
            switch sortOption {
            case .title:
                result = lhs.song.displayTitle.localizedCaseInsensitiveCompare(rhs.song.displayTitle)
            case .artist:
                result = (lhs.song.artist ?? "").localizedCaseInsensitiveCompare(rhs.song.artist ?? "")
            case .album:
                result = (lhs.song.album ?? "").localizedCaseInsensitiveCompare(rhs.song.album ?? "")
            case .duration:
                result = NSNumber(value: lhs.song.duration ?? 0).compare(NSNumber(value: rhs.song.duration ?? 0))
            case .rating:
                result = NSNumber(value: lhs.song.userRating ?? 0).compare(NSNumber(value: rhs.song.userRating ?? 0))
            case .playCount:
                result = NSNumber(value: lhs.song.playCount ?? 0).compare(NSNumber(value: rhs.song.playCount ?? 0))
            case .added:
                result = (lhs.song.created ?? "").compare(rhs.song.created ?? "")
            case .playlistOrder:
                result = .orderedSame
            }
            if result == .orderedSame {
                return lhs.playlistIndex < rhs.playlistIndex
            }
            return sortAscending ? (result == .orderedAscending) : (result == .orderedDescending)
        }
    }

    var filteredIndexedRows: [(playlistIndex: Int, song: SubsonicSong)] {
        guard !filterText.isEmpty else { return sortedIndexedRows }
        let query = filterText.localizedLowercase
        return sortedIndexedRows.filter {
            $0.song.displayTitle.localizedLowercase.contains(query) ||
            ($0.song.artist?.localizedLowercase.contains(query) ?? false) ||
            ($0.song.album?.localizedLowercase.contains(query) ?? false)
        }
    }

    var isReorderingEnabled: Bool {
        !currentDetail.isSmart &&
        app.canEditPlaylist(currentDetail.summary) &&
        filterText.isEmpty &&
        sortOption == .playlistOrder &&
        sortAscending &&
        !app.isOfflineSession
    }

    var currentDetail: PlaylistDetail {
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

    func header(_ detail: PlaylistDetail) -> some View {
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
                        SelectableHeaderText(
                            text: detail.displayName,
                            font: SelectableHeaderText.font(for: .largeTitle, weight: .semibold),
                            color: .labelColor
                        )
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

    func editRulesButton(_ detail: PlaylistDetail) -> some View {
        EditRulesButton {
            app.openSmartPlaylistEditor(server: ServerSmartPlaylist(summary: detail.summary))
        }
    }

    func commentButton(title: String, comment: String) -> some View {
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
    private var identifiedSongs: [PlaylistIndexedSong] {
        var counts: [String: Int] = [:]
        var result: [PlaylistIndexedSong] = []

        for (displayIdx, item) in filteredIndexedRows.prefix(displayedCount).enumerated() {
            let occ = counts[item.song.id, default: 0]
            counts[item.song.id] = occ + 1
            let id = occ == 0 ? item.song.id : "\(item.song.id)_\(occ)"

            result.append(PlaylistIndexedSong(
                displayIndex: displayIdx,
                playlistIndex: item.playlistIndex,
                song: item.song,
                id: id
            ))
        }
        return result
    }

    private var currentSongID: String? {
        app.player.currentSong?.id
    }
}
