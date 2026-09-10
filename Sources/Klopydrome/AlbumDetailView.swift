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

    private var songs: [SubsonicSong] { detail?.song ?? [] }

    private var isLossless: Bool {
        songs.contains { PlaybackFormat.isLossless($0.suffix) }
    }

    var body: some View {
        Group {
            if detail != nil || loading {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                }
            } else {
                ContentUnavailableView("Альбом недоступен", systemImage: "rectangle.slash")
            }
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
    private var skeletonRows: some View {
        LazyVStack(spacing: 0) {
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
            QuickLookCover(coverArt: detail.coverArt)
                .frame(width: 220, height: 220)
                .help("Нажмите или сильный клик для предпросмотра — как в Finder")
                .accessibilityLabel("Предпросмотр обложки")
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
            NavigationLink(value: Artist(id: artistId, name: artist)) {
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
        if isLossless { parts.append("Lossless") }
        return HStack(spacing: 6) {
            Text(parts.joined(separator: " · "))
            if isLossless {
                Image(systemName: "waveform.mid")
                    .font(.system(size: 13))
            }
        }
        .font(.callout)
        .foregroundStyle(AMColor.secondaryText)
    }

    // MARK: Action row

    private var actionRow: some View {
        HStack(spacing: 10) {
            ActionPill(title: "Слушать", systemImage: "play.fill", filled: true) {
                if !songs.isEmpty { app.play(songs, at: 0) }
            }
            ActionPill(title: "Перемешать", systemImage: "shuffle", filled: true) {
                if !songs.isEmpty { app.playShuffled(songs) }
            }
            Spacer()
            RoundEllipsisMenu {
                AlbumContextMenuItems(album: album)
            }
            .help("Действия над альбомом")
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

    private func trackList(_ detail: AlbumDetail) -> some View {
        let currentID = app.player.currentSong?.id
        let groups = groupedSongs
        let ordered = orderedSongs
        // O(1) lookup for global index instead of O(n) firstIndex per song.
        let indexByID: [String: Int] = Dictionary(
            uniqueKeysWithValues: ordered.enumerated().map { ($0.element.id, $0.offset) }
        )
        let showDiscHeaders = groups.count > 1
        return VStack(alignment: .leading, spacing: 16) {
            LazyVStack(spacing: 0) {
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
                        let displayIndex: Int? = song.track.map { $0 - 1 }
                        SongRow(song: song, index: displayIndex, showAlbum: false,
                                isCurrentOverride: currentID == song.id,
                                onPlay: { _ in app.play(ordered, at: globalIndex) })
                        if song.id != group.songs.last?.id { Divider().opacity(0.3) }
                    }
                    if showDiscHeaders && group.disc != groups.last?.disc {
                        Divider().opacity(0.2).padding(.vertical, 4)
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
            detail = app.offlineAlbumDetail(for: albumID)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: Artist(id: artistId, name: artistName)) {
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
            if albums.isEmpty {
                ProgressView()
                    .padding(.vertical, 20)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(albums) { album in
                            NavigationLink(value: album) {
                                AlbumCard(album: album, width: 160)
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

    private func load() async {
        guard albums.isEmpty, let client = app.client else { return }
        let artist = try? await client.getArtist(id: artistId)
        albums = artist?.album ?? []
    }
}