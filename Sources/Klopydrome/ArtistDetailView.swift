import SwiftUI
import NavidromeClient

struct ArtistDetailView: View {
    let artist: Artist
    @Environment(AppState.self) private var app

    @State private var detail: ArtistDetail?
    @State private var loading = true
    @State private var topSongs: [SubsonicSong]?
    /// Every song of the artist, fetched once by `load()` and reused by
    /// "Gather & Play" instead of issuing a duplicate request burst.
    @State private var allSongs: [SubsonicSong] = []
    @State private var gatheringSongs = false
    @State private var playHovered = false
    @State private var releaseHovered = false
    /// The discography crawl, spawned in the background by `load()` so the page
    /// renders the instant the (fast) artist info lands. Cancelled when this
    /// view goes away. "Gather & Play" awaits it instead of issuing a fresh
    /// request burst.
    @State private var discographyTask: Task<Void, Never>?

    /// Albums fetched concurrently at a time; keeps a big artist from issuing
    /// hundreds of simultaneous album requests to the server.
    private let albumBatchSize = 8

    /// Sort chosen for the album shelf; defaults to release date.
    @State private var albumSort: ArtistAlbumSort = .release
    /// Albums this artist appears on without being the lead/album artist.
    @State private var appearsOn: [SubsonicAlbum] = []
    /// Expands the album shelf into a full grid when true; the header chevron toggles it.
    @State private var albumsExpanded = false
/// Sort direction for the album shelf/grid (descending = newest first by default).
    @State private var albumsDescending = true

    private var albums: [SubsonicAlbum] {
        let source = detail?.album ?? []
        return sortedAlbums(source, by: albumSort, descending: albumsDescending)
    }

    /// The most recent album, picked from the raw list — never from the
    /// sorted one, so the tile is stable while the sort key/direction
    /// changes. Ties on the max year break by name for a deterministic pick.
    private var latestReleaseCandidate: SubsonicAlbum? {
        (detail?.album ?? []).max { lhs, rhs in
            let lhsYear = lhs.year ?? 0
            let rhsYear = rhs.year ?? 0
            if lhsYear != rhsYear { return lhsYear < rhsYear }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    /// Role label inferred from the OpenSubsonic `roles` tag when present,
    /// otherwise from the artist's own songs (artist vs albumArtist).
    private var roleLabel: String? {
        ArtistRole.playlistLabel(roles: detail?.roles, songs: allSongs)
    }

    var body: some View {
        Group {
            if let detail {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        header(detail)
                        if let latest = latestReleaseCandidate {
                            latestRelease(latest)
                        }
                        if !albums.isEmpty {
                            albumsShelf
                        }
                        if !appearsOn.isEmpty {
                            appearsOnSection()
                        }
                        if let top = topSongs, !top.isEmpty {
                            topSongsSection(top)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                }
                .scrollClipDisabled()
            } else if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("Исполнитель недоступен", systemImage: "music.mic")
            }
        }
        .task { await load() }
        .onDisappear { discographyTask?.cancel() }
    }

    // MARK: Header

    private func header(_ detail: ArtistDetail) -> some View {
        HStack(spacing: 20) {
            Button {
                gatherAndPlay()
            } label: {
                Group {
                    if gatheringSongs {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 52, height: 52)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(Circle().fill(AMColor.accent))
                            .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                            .scaleEffect(playHovered ? 1.08 : 1)
                            .brightness(playHovered ? 0.08 : 0)
                            .animation(.snappy(duration: 0.15), value: playHovered)
                    }
                }
            }
            .buttonStyle(.plain)
            .onHover { playHovered = $0 }
            .help("Слушать исполнителя")
            .accessibilityLabel("Слушать исполнителя")

            VStack(alignment: .leading, spacing: 4) {
                Text(detail.name ?? artist.name)
                    .font(.largeTitle.bold())
                Text(roleLabel ?? "Исполнитель")
                    .font(.subheadline)
                    .foregroundStyle(AMColor.secondaryText)
                if let count = detail.albumCount {
                    Text("\(count) \(Pluralized.album(count))")
                        .font(.subheadline)
                        .foregroundStyle(AMColor.secondaryText)
                }
            }
            Spacer()
        }
    }

    private func latestRelease(_ latest: SubsonicAlbum) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Последний релиз".localized)
                .font(.title2.bold())
            NavigationLink(value: latest) {
                HStack(spacing: 16) {
                    CoverArtView(coverArt: latest.coverArt, size: 150, shadow: true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(latest.displayName)
                            .font(.title3.weight(.semibold))
                        Text(latest.artist ?? artist.name)
                            .font(.subheadline)
                            .foregroundStyle(AMColor.secondaryText)
                        if let year = latest.year {
                            Text(String(year))
                                .font(.caption)
                                .foregroundStyle(AMColor.secondaryText)
                        }
                    }
                }
                .padding(.trailing, 12)
                .contentShape(Rectangle())
                .brightness(releaseHovered ? 0.08 : 0)
                .animation(.snappy(duration: 0.15), value: releaseHovered)
            }
            .buttonStyle(.plain)
            .onHover { releaseHovered = $0 }
        }
    }

    private func appearsOnSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("Появляется на".localized)
                    .font(.title2.bold())
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(appearsOn) { album in
                        NavigationLink(value: album) {
                            AlbumCard(album: album, width: 150, showsYear: true, reservesTitleLines: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
            }
            .scrollClipDisabled()
        }
    }

    private func topSongsSection(_ top: [SubsonicSong]) -> some View {
        let currentID = app.player.currentSong?.id
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("Лучшие песни".localized)
                    .font(.title2.bold())
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            LazyVStack(spacing: 0) {
                ForEach(Array(top.enumerated()), id: \.element.id) { index, song in
                    SongRow(song: song, index: index, showAlbum: true,
                            isCurrentOverride: currentID == song.id,
                            onPlay: { idx in app.play(top, at: idx) })
                    if index < top.count - 1 { Divider().opacity(0.3) }
                }
            }
        }
    }

    // MARK: Actions

    private func gatherAndPlay() {
        guard !gatheringSongs else { return }
        gatheringSongs = true
        Task {
            defer { gatheringSongs = false }
            if allSongs.isEmpty {
                // Reuse the in-flight background crawl if one is running;
                // otherwise run it now.
                await discographyTask?.value
                if allSongs.isEmpty {
                    allSongs = await allAlbumSongs()
                }
            }
            if !allSongs.isEmpty { app.play(allSongs, at: 0) }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        guard let client = app.client else { return }
        detail = try? await client.getArtist(id: artist.id)
        // If the full discography was already crawled during this connection,
        // replay it from the cache instead of re-fetching every album's tracklist.
        if let cached = await app.cache?.cachedDiscography(for: artist.id) {
            allSongs = cached
            topSongs = Array(cached.sorted { ($0.playCount ?? 0) > ($1.playCount ?? 0) }.prefix(10))
            discographyTask?.cancel()
            discographyTask = nil
        } else {
            // The long discography crawl runs in the background, so the header
            // and album shelf render as soon as the (fast) artist info lands.
            // Top songs fill in progressively as album batches finish, and any
            // previous crawl for this view is restarted/cancelled cleanly.
            discographyTask?.cancel()
            discographyTask = Task {
                await crawlDiscography()
                // Only cache a fully-completed crawl; a cancelled or empty one
                // must not poison the cache for the next visit.
                if !Task.isCancelled, !allSongs.isEmpty {
                    await app.cache?.cacheDiscography(allSongs, for: artist.id)
                }
            }
        }
        await loadAppearsOn(client: client)
    }

    /// Fetches albums this artist appears on without being the lead artist:
    /// search3 for the artist name, pick songs where they're the track artist
    /// on an album they don't lead, deduplicated by album id.
    private func loadAppearsOn(client: SubsonicClient) async {
        let name = detail?.name ?? artist.name
        guard !name.isEmpty else { return }
        let result = try? await client.search3(query: name, artistCount: 0, albumCount: 0, songCount: 200)
        guard let songs = result?.songs else { return }
        let artistID = artist.id
        let artistName = name.lowercased()
        let seen = Set(albums.map(\.id))
        var grouped: [String: SubsonicSong] = [:]
        for song in songs {
            guard song.artistId == artistID else { continue }
            let albumID = song.albumId ?? ""
            guard !albumID.isEmpty, !seen.contains(albumID) else { continue }
            // Skip songs where this artist leads the album (album artist matches).
            if let albumArtist = song.albumArtist, albumArtist.lowercased() == artistName { continue }
            if grouped[albumID] == nil { grouped[albumID] = song }
        }
        let made = grouped.values.compactMap { song -> SubsonicAlbum? in
            guard let albumID = song.albumId, !albumID.isEmpty else { return nil }
            return SubsonicAlbum(
                id: albumID,
                title: song.album,
                album: song.album,
                artist: song.albumArtist,
                coverArt: song.coverArt)
        }
        appearsOn = made.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
}

/// Role label for an artist, from OpenSubsonic `roles` when present; otherwise
/// a plain "Исполнитель" fallback. Roles are authoritative — the server pushes
/// them via `getArtist`, so we don't try to second-guess from song fields.
enum ArtistRole {
    static func playlistLabel(roles: [String]?, songs: [SubsonicSong]) -> String? {
        if let roles, !roles.isEmpty {
            var labels: [String] = []
            if roles.contains("composer") { labels.append("Композитор") }
            if roles.contains("albumartist") { labels.append("Автор альбома") }
            if roles.contains("artist") { labels.append("Исполнитель") }
            if !labels.isEmpty {
                return labels.joined(separator: " · ")
            }
        }
        return "Исполнитель"
    }
}

// MARK: - Discography crawl

/// Album shelf + grid builders for the artist page, kept out of the main struct
/// body so `ArtistDetailView` stays under the `type_body_length` budget.
private extension ArtistDetailView {
    /// The album section: a header that toggles between the horizontal shelf
    /// and a full grid of the artist's albums, without leaving the page.
    var albumsShelf: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(Motion.spring(Motion.expand)) {
                        albumsExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("Альбомы".localized)
                            .font(.title2.bold())
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(albumsExpanded ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(albumsExpanded ? "Свернуть альбомы" : "Раскрыть альбомы сеткой")
                .accessibilityLabel(albumsExpanded ? "Свернуть альбомы" : "Раскрыть альбомы сеткой")
                Spacer()
                AlbumSortMenu(sort: $albumSort, descending: $albumsDescending)
            }
            if albumsExpanded {
                albumsGrid
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(albums) { album in
                            NavigationLink(value: album) {
                                AlbumCard(album: album, width: 150, showsYear: true, reservesTitleLines: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                }
                .scrollClipDisabled()
            }
        }
    }

    /// The discography as a compact adaptive grid (150pt cards), shown when the
    /// album section is expanded. Smaller than the Albums tab grid so more
    /// columns fit and cells hug the cards instead of leaving dead space.
    var albumsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            ForEach(albums) { album in
                NavigationLink(value: album) {
                    AlbumCard(album: album, width: 150, showsYear: true, reservesTitleLines: true)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Fetches every album of the artist (sequentially batched), returning the
    /// concatenated songs. Serves the connection-local cache on revisits.
    func allAlbumSongs() async -> [SubsonicSong] {
        if let cached = await app.cache?.cachedDiscography(for: artist.id) {
            return cached
        }
        guard let client = app.client else { return [] }
        let ids = albums.map(\.id)
        var all: [SubsonicSong] = []
        var start = 0
        while start < ids.count {
            if Task.isCancelled { break }
            let end = min(start + albumBatchSize, ids.count)
            await withTaskGroup(of: [SubsonicSong].self) { group in
                for id in ids[start..<end] {
                    group.addTask {
                        try? Task.checkCancellation()
                        return (try? await client.getAlbum(id: id))?.song ?? []
                    }
                }
                for await songs in group {
                    all.append(contentsOf: songs)
                }
            }
            start = end
        }
        return all
    }

    /// Crawls every album's tracklist in batches of `albumBatchSize`, updating
    /// `allSongs` and the top-songs shelf as each batch lands — the page stays
    /// responsive and top songs appear before the crawl drains a large
    /// discography.
    func crawlDiscography() async {
        guard let client = app.client else { return }
        let ids = albums.map(\.id)
        var results: [SubsonicSong] = []
        var start = 0
        while start < ids.count {
            if Task.isCancelled { break }
            let end = min(start + albumBatchSize, ids.count)
            let batch = await withTaskGroup(of: [SubsonicSong].self) { group in
                for id in ids[start..<end] {
                    group.addTask {
                        try? Task.checkCancellation()
                        return (try? await client.getAlbum(id: id))?.song ?? []
                    }
                }
                var chunk: [SubsonicSong] = []
                for await songs in group {
                    chunk.append(contentsOf: songs)
                }
                return chunk
            }
            results.append(contentsOf: batch)
            if !Task.isCancelled {
                allSongs = results
                let sorted = results.sorted { ($0.playCount ?? 0) > ($1.playCount ?? 0) }
                topSongs = Array(sorted.prefix(10))
            }
            start = end
            await Task.yield()
        }
    }
}