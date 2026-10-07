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
    @State private var loading = true
    @State private var artistHovered = false
    @State private var selection = SongRowSelection()

    private var songs: [SubsonicSong] { detail?.song ?? [] }

    private var isLossless: Bool {
        songs.contains { PlaybackFormat.isLossless($0.suffix) }
    }

    var body: some View {
        Group {
            if detail != nil || loading {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        header(displayedDetail)
                        if songs.isEmpty && loading {
                            skeletonRows
                        } else {
                            trackList(displayedDetail)
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
            } else {
                ContentUnavailableView("Альбом недоступен", systemImage: "rectangle.slash")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    private var skeletonRows: some View {
        VStack(spacing: 0) {
            ForEach(0..<10, id: \.self) { _ in
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
    }

    // MARK: Header

    private func header(_ detail: AlbumDetail) -> some View {
        HStack(alignment: .top, spacing: 24) {
            QuickLookCover(coverArt: detail.coverArt, title: detail.displayName)
                .frame(width: 220, height: 220)
                .help("Быстрый просмотр обложки".localized)
                .accessibilityLabel("Предпросмотр обложки".localized)
            VStack(alignment: .leading, spacing: 10) {
                Text(detail.displayName)
                    .font(.largeTitle.bold())
                artistLink(detail)
                metaRow(detail)
                Spacer(minLength: 0)
                actionRow
            }
            .frame(minHeight: 200)
            .padding(.top, 4)
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
                    .font(.title3.weight(.medium))
                    .foregroundStyle(AMColor.accent)
                    .brightness(artistHovered ? 0.15 : 0)
                    .animation(.snappy(duration: 0.15), value: artistHovered)
            }
            .buttonStyle(.plain)
            .onHover { artistHovered = $0 }
        } else if !artist.isEmpty {
            Text(artist)
                .font(.title3.weight(.medium))
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
        return HStack(spacing: 8) {
            Text(parts.joined(separator: " · "))
                .font(.callout)
                .foregroundStyle(AMColor.secondaryText)
            if isLossless {
                HStack(spacing: 4) {
                    Image(systemName: "waveform.mid")
                        .font(.system(size: 9, weight: .bold))
                    Text("Lossless")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(Color.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 0.8)
                )
                .help("Аудио без потерь".localized)
            }
        }
    }

    // MARK: Action row

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
                RoundFavoriteButton(isStarred: app.isStarred(album)) {
                    app.toggleStar(album)
                }
                RoundEllipsisMenu {
                    AlbumContextMenuItems(album: album)
                }
                .help("Действия над альбомом".localized)
            }
        }
    }

    // MARK: Track list + footer

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
        if let recordType = detail.recordType?.lowercased(), recordType == "compilation" {
            return true
        }
        if let artist = detail.artist?.lowercased(),
           artist == "various artists" || artist == "разные артисты" || artist == "soundtrack" {
            return true
        }
        let artists = Set(songs.compactMap { $0.artist })
        return artists.count > 1
    }

    private func playTrack(_ song: SubsonicSong, globalIndex: Int, ordered: [SubsonicSong]) {
        if app.isOfflineSession {
            let playable = playableSongs
            let playIndex = playable.firstIndex(where: { $0.id == song.id }) ?? 0
            app.play(playable, at: playIndex)
        } else {
            app.play(ordered, at: globalIndex)
        }
    }

    private func trackList(_ detail: AlbumDetail) -> some View {
        let currentID = app.player.currentSong?.id
        let groups = groupedSongs
        let ordered = orderedSongs
        let isCompilation = isCompilationAlbum(detail)
        // O(1) lookup for global index instead of O(n) firstIndex per song.
        let indexByID: [String: Int] = Dictionary(
            uniqueKeysWithValues: ordered.enumerated().map { ($0.element.id, $0.offset) }
        )
        let showDiscHeaders = groups.count > 1
        return VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 0) {
                ForEach(Array(groups.enumerated()), id: \.element.disc) { _, group in
                    if showDiscHeaders {
                        Text(String(format: "Диск %d".localized, group.disc))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
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
            footer(detail)
        }
    }

    private func footer(_ detail: AlbumDetail) -> some View {
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

    private var createdDate: String? {
        SubsonicDate.longDate(detail?.created)
    }

    private func load() async {
        let albumID = album.id
        let isOffline = app.isOfflineSession
        detail = nil
        loading = true
        defer {
            if !Task.isCancelled { loading = false }
        }

        if isOffline {
            detail = await app.offlineAlbumDetail(for: albumID)
            return
        }
        guard let client = app.client else { return }
        let loadedDetail = try? await client.getAlbum(id: albumID)
        guard !Task.isCancelled else { return }
        detail = loadedDetail
        if let loadedDetail { await app.persistOfflineAlbumDetail(loadedDetail) }
    }
}

/// Horizontal shelf of an artist's other albums.
private struct MoreByArtist: View {
    let artistId: String
    let artistName: String
    @Environment(AppState.self) private var app

    @State private var albums: [SubsonicAlbum] = []
    @State private var loaded = false

    var body: some View {
        if !albums.isEmpty || !loaded {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    app.openArtistInLibrary(Artist(id: artistId, name: artistName))
                } label: {
                    HStack(spacing: 6) {
                        Text(L10n.format("format.album.moreByArtist", artistName))
                            .font(.title2.bold())
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if !loaded {
                    ProgressView()
                        .padding(.vertical, 20)
                } else if !albums.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(albums) { album in
                                Button {
                                    app.openAlbumInLibrary(album)
                                } label: {
                                    AlbumCard(album: album)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.bottom, 4)
                    }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        guard albums.isEmpty, !loaded else { return }
        if app.isOfflineSession {
            albums = app.library.albums.filter {
                ($0.artistId != nil && $0.artistId == artistId) ||
                ($0.artist != nil && $0.artist == artistName)
            }
            loaded = true
            return
        }
        guard let client = app.client else {
            loaded = true
            return
        }
        defer { loaded = true }
        let artist = try? await client.getArtist(id: artistId)
        albums = artist?.album ?? []
    }
}