import SwiftUI
import NavidromeClient

struct AlbumDetailView: View {
    private struct LoadID: Hashable {
        let albumID: String
        let offlineSession: Bool
    }

    let album: SubsonicAlbum
    @Environment(AppState.self) private var app

    @State private var detail: AlbumDetail?
    @State private var albumInfo: AlbumInfoPayload?
    @State private var isNotesExpanded = false
    @State private var loading = true
    @State private var isSyncing = false
    @State private var artistHovered = false
    @State private var selection = SongRowSelection()

    private var songs: [SubsonicSong] { detail?.song ?? [] }

    private var isLossless: Bool {
        songs.contains { PlaybackFormat.isLossless($0.suffix) }
    }

    @State private var loadError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header(displayedDetail)
                if songs.isEmpty && loading {
                    skeletonRows
                        .padding(.leading, -22)
                        .padding(.trailing, 26)
                } else if songs.isEmpty, let loadError {
                    emptyErrorState(loadError)
                } else {
                    if let loadError {
                        inlineErrorNotice(loadError)
                    }
                    AlbumTrackListSection(
                        detail: displayedDetail,
                        songs: songs,
                        app: app,
                        selection: $selection,
                        createdDate: createdDate
                    )
                }
                if let notes = albumInfo?.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    albumNotesSection(notes)
                }
                if let artistId = displayedDetail.artistId ?? album.artistId,
                   let name = displayedDetail.artist ?? album.artist, !artistId.isEmpty {
                    MoreByArtist(artistId: artistId, artistName: name)
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .refreshable {
            await load(forceReload: true)
        }
        .task(id: LoadID(albumID: album.id, offlineSession: app.isOfflineSession)) {
            await load()
        }
    }

    /// Header data is available immediately from the summary the grid navigated
    /// with, so the top section renders without waiting for the song fetch.
    private var displayedDetail: AlbumDetail {
        detail ?? AlbumDetail(
            id: album.id,
            name: album.title ?? album.album ?? album.name,
            artist: album.artist,
            artistId: album.artistId,
            coverArt: album.coverArt,
            songCount: album.songCount,
            duration: album.duration,
            created: album.created,
            year: album.year,
            genre: album.genre,
            starred: album.starred
        )
    }

    /// Placeholder track rows shown while the album's songs stream in.
    /// Standard album tracks are narrow (32pt, single line) without artwork.
    private var skeletonRows: some View {
        SkeletonSongList(count: 10, showAlbum: false, showsArtist: false)
    }

    // MARK: Header

    private func header(_ detail: AlbumDetail) -> some View {
        HStack(alignment: .top, spacing: 24) {
            QuickLookCover(coverArt: detail.coverArt, title: detail.displayName)
                .frame(width: 220, height: 220)
                .help("Быстрый просмотр обложки".localized)
                .accessibilityLabel("Предпросмотр обложки".localized)
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 4) {
                    Text(detail.displayName)
                        .font(.largeTitle.weight(.semibold))
                    artistLink(detail)
                    metaRow(detail)
                }
                .offset(y: -6)
                Spacer(minLength: 0)
                actionRow
            }
            .frame(minHeight: 220)
            Spacer()
        }
    }

    @ViewBuilder
    private func artistLink(_ detail: AlbumDetail) -> some View {
        let artist = detail.artist ?? album.artist ?? ""
        let artistId = detail.artistId ?? album.artistId ?? ""
        if !artistId.isEmpty {
            Button {
                app.openArtistInLibrary(Artist(id: artistId, name: artist))
            } label: {
                Text(artist)
                    .font(.title2.weight(.regular))
                    .foregroundStyle(AMColor.accent)
                    .brightness(artistHovered ? 0.15 : 0)
            }
            .buttonStyle(.plain)
            .onHover { artistHovered = $0 }
        } else if !artist.isEmpty {
            Text(artist)
                .font(.title2.weight(.regular))
        }
    }

    private func metaRow(_ detail: AlbumDetail) -> some View {
        var parts: [String] = []
        if let genre = detail.genre, !genre.isEmpty { parts.append(genre) }
        if let year = detail.year { parts.append(String(year)) }
        let total = songs.reduce(0) { $0 + ($1.duration ?? 0) }
        if !songs.isEmpty {
            parts.append("\(songs.count) \(Pluralized.song(songs.count)) · \(Player.format(seconds: Double(total)))")
        } else if let count = detail.songCount {
            parts.append("\(count) \(Pluralized.song(count))")
        }
        if isLossless {
            parts.append("Lossless")
        }
        return Text(parts.joined(separator: " · "))
            .font(.callout.bold())
            .foregroundStyle(AMColor.secondaryText)
    }

    // MARK: Action row

    private var orderedSongs: [SubsonicSong] {
        let grouped = Dictionary(grouping: songs, by: { $0.discNumber ?? 1 })
        return grouped.keys.sorted().flatMap { disc in
            grouped[disc]!.sorted { ($0.track ?? 0) < ($1.track ?? 0) }
        }
    }

    private var playableSongs: [SubsonicSong] {
        if app.isOfflineSession {
            return orderedSongs.filter { app.isCached($0) }
        }
        return orderedSongs
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            ActionPill(title: "Слушать", systemImage: "play.fill", filled: true) {
                if !playableSongs.isEmpty { app.play(playableSongs, at: 0) }
            }
            .disabled(playableSongs.isEmpty)
            ActionPill(title: "Перемешать", systemImage: "shuffle", filled: true) {
                if !playableSongs.isEmpty { app.playShuffled(playableSongs) }
            }
            .disabled(playableSongs.isEmpty)
            Spacer()
            HStack(spacing: 8) {
                if isSyncing {
                    ProgressView()
                        .controlSize(.small)
                        .help("Синхронизация с сервером…".localized)
                        .transition(.opacity)
                }
                RoundFavoriteButton(isStarred: app.isStarred(album)) {
                    app.toggleStar(album)
                }
                RoundEllipsisMenu {
                    AlbumContextMenuItems(album: album)
                }
                .help("Действия над альбомом".localized)
            }
            .animation(.easeInOut(duration: 0.2), value: isSyncing)
        }
    }

}

// MARK: - Album Track List Section

private struct AlbumTrackListSection: View {
    let detail: AlbumDetail
    let songs: [SubsonicSong]
    let app: AppState
    @Binding var selection: SongRowSelection
    let createdDate: String?

    private var groupedSongs: [(disc: Int, songs: [SubsonicSong])] {
        let grouped = Dictionary(grouping: songs, by: { $0.discNumber ?? 1 })
        return grouped.keys.sorted().map { disc in
            let list = grouped[disc]!.sorted { ($0.track ?? 0) < ($1.track ?? 0) }
            return (disc, list)
        }
    }

    private var orderedSongs: [SubsonicSong] {
        groupedSongs.flatMap(\.songs)
    }

    private func isCompilationAlbum(_ detail: AlbumDetail) -> Bool {
        Set(songs.compactMap(\.artist)).count > 1
    }

    private func playTrack(_ song: SubsonicSong, globalIndex: Int, ordered: [SubsonicSong]) {
        if app.isOfflineSession {
            let playable = songs.filter { app.isCached($0) }
            let playIndex = playable.firstIndex(where: { $0.id == song.id }) ?? 0
            app.play(playable, at: playIndex)
        } else {
            app.play(ordered, at: globalIndex)
        }
    }

    var body: some View {
        let currentID = app.player.currentSong?.id
        let groups = groupedSongs
        let ordered = orderedSongs
        let isCompilation = isCompilationAlbum(detail)
        let indexByID: [String: Int] = Dictionary(
            uniqueKeysWithValues: ordered.enumerated().map { ($0.element.id, $0.offset) }
        )
        let showDiscHeaders = groups.count > 1

        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 0) {
                ForEach(Array(groups.enumerated()), id: \.element.disc) { _, group in
                    if showDiscHeaders {
                        Text(String(format: "Диск %d".localized, group.disc))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 30)
                            .padding(.trailing, 8)
                            .padding(.vertical, 6)
                    }
                    ForEach(group.songs, id: \.id) { song in
                        let globalIndex = indexByID[song.id] ?? 0
                        let displayIndex: Int = song.track.map { $0 - 1 } ?? globalIndex
                        let isDifferent = song.artist != nil &&
                            song.artist?.localizedCaseInsensitiveCompare(detail.artist ?? "") != .orderedSame
                        let rowShowsArtist = isCompilation || isDifferent
                        SongRow(
                            song: song,
                            index: displayIndex,
                            showAlbum: false,
                            showsArtist: rowShowsArtist,
                            isCurrentOverride: currentID == song.id,
                            onPlay: { _ in playTrack(song, globalIndex: globalIndex, ordered: ordered) },
                            isSelected: selection.isSelected(song.id),
                            resolveSelection: { selection.selectedSongs(from: ordered) },
                            onSelect: { selection.toggle(song.id, allSongs: ordered) }
                        )
                        .equatable()
                    }
                    if showDiscHeaders && group.disc != groups.last?.disc {
                        Color.clear.frame(height: 3)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, -22)
            .padding(.trailing, 26)

            VStack(alignment: .leading, spacing: 2) {
                let total = songs.reduce(0) { $0 + ($1.duration ?? 0) }
                Text("\(songs.count) \(Pluralized.song(songs.count)) · \(Player.format(seconds: Double(total)))")
                if let created = createdDate {
                    Text(created)
                }
            }
            .font(.callout)
            .foregroundStyle(AMColor.secondaryText)
            .padding(.top, 4)
        }
    }
}

// MARK: - Load & Helpers

extension AlbumDetailView {
    func emptyErrorState(_ error: String) -> some View {
        DetailUnavailableView(message: error) {
            Task { await load() }
        }
    }

    func inlineErrorNotice(_ error: String) -> some View {
        DetailInlineErrorBanner(message: error) {
            Task { await load() }
        }
    }

    var createdDate: String? {
        SubsonicDate.longDate(detail?.created)
    }

    func load(forceReload: Bool = false) async {
        let albumID = album.id
        loadError = nil

        if app.isOfflineSession {
            await loadOffline(albumID: albumID)
            return
        }

        if !forceReload {
            _ = await applyCachedAlbumDetail(albumID: albumID)
        }

        await fetchOnlineAlbumDetail(albumID: albumID)
    }

    private func loadOffline(albumID: String) async {
        loading = true
        defer {
            if !Task.isCancelled { loading = false }
        }
        let offline = await app.offlineAlbumDetail(for: albumID)
        if !Task.isCancelled {
            detail = offline
        }
    }

    private func applyCachedAlbumDetail(albumID: String) async -> Bool {
        guard let cached = await app.cachedAlbumDetail(for: albumID) else { return false }
        guard !Task.isCancelled else { return false }
        detail = cached
        loading = false
        return true
    }

    private func fetchOnlineAlbumDetail(albumID: String) async {
        guard let client = app.client else {
            loading = false
            return
        }

        if detail == nil {
            loading = true
        }
        isSyncing = true
        defer {
            if !Task.isCancelled {
                loading = false
                isSyncing = false
            }
        }

        do {
            async let albumTask = client.getAlbum(id: albumID)
            async let infoTask: AlbumInfoPayload? = try? await client.getAlbumInfo2(id: albumID)
            let (loadedDetail, loadedInfo) = await (try albumTask, infoTask)
            guard !Task.isCancelled else { return }
            detail = loadedDetail
            albumInfo = loadedInfo
            await app.persistAlbumDetail(loadedDetail)
            await app.persistOfflineAlbumDetail(loadedDetail)
        } catch {
            guard !Task.isCancelled else { return }
            if detail == nil {
                detail = await app.offlineAlbumDetail(for: albumID)
            }
            loadError = error.localizedDescription
        }
    }

    @ViewBuilder
    private func albumNotesSection(_ rawNotes: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Об альбоме".localized)
                .font(.title3.bold())

            VStack(alignment: .leading, spacing: 6) {
                Text(cleanNotes(rawNotes))
                    .font(.callout)
                    .foregroundStyle(AMColor.secondaryText)
                    .lineSpacing(3)
                    .lineLimit(isNotesExpanded ? nil : 4)
                    .textSelection(.enabled)

                if rawNotes.count > 220 {
                    Button(isNotesExpanded ? "Меньше".localized : "Подробнее".localized) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isNotesExpanded.toggle()
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                }
            }
        }
        .padding(.top, 4)
    }

    private func cleanNotes(_ raw: String) -> LocalizedStringKey {
        var text = raw
        if let lastFm = albumInfo?.lastFmUrl, !lastFm.isEmpty {
            text = text.replacingOccurrences(
                of: "<a href=\"[^\"]+\">Read more on Last.fm</a>",
                with: "[Read more on Last.fm](\(lastFm))",
                options: .regularExpression
            )
            text = text.replacingOccurrences(
                of: "Read more on Last.fm",
                with: "[Read more on Last.fm](\(lastFm))"
            )
        }
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return LocalizedStringKey(text)
    }
}