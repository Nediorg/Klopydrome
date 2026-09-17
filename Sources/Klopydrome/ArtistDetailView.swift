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
    @State private var artistInfo: ArtistInfoPayload?
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
    /// identifying the artist's primary role (album artist vs composer vs guest).
    private var roleLabel: String? {
        ArtistRole.primaryRole(
            roles: detail?.roles,
            hasAlbums: !(albums.isEmpty && (detail?.albumCount ?? 0) == 0),
            songs: allSongs
        )
    }

    var body: some View {
        Group {
            if let detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        ArtistHeroBanner(
                            artist: artist,
                            detail: detail,
                            roleLabel: roleLabel,
                            albums: albums,
                            allSongs: allSongs,
                            artistInfo: artistInfo,
                            gatheringSongs: gatheringSongs,
                            onPlay: { gatherAndPlay() }
                        )

                        VStack(alignment: .leading, spacing: 28) {
                            ArtistHeroRow(artist: artist, latest: latestReleaseCandidate, top: topSongs)
                            if !albums.isEmpty {
                                albumsShelf
                            }
                            if !appearsOn.isEmpty {
                                appearsOnSection()
                            }
                        }
                        .padding(.horizontal, 28)
                        .padding(.bottom, 24)
                    }
                }
                .scrollClipDisabled()
            } else if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("Исполнитель недоступен", systemImage: "music.mic")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await load() }
        .onDisappear { discographyTask?.cancel() }
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
                HStack(alignment: .top, spacing: 12) {
                    ForEach(appearsOn) { album in
                        Button {
                            app.openAlbumInLibrary(album)
                        } label: {
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
        var resolvedID = artist.id
        var fetchedDetail = try? await client.getArtist(id: resolvedID)
        if fetchedDetail == nil {
            if let matched = app.library.findArtist(named: artist.name) {
                resolvedID = matched.id
                fetchedDetail = try? await client.getArtist(id: resolvedID)
            } else if let search = try? await client.search3(query: artist.name),
                      let match = search.artists.first(where: {
                          $0.name.localizedCaseInsensitiveCompare(artist.name) == .orderedSame
                      }) {
                resolvedID = match.id
                fetchedDetail = try? await client.getArtist(id: resolvedID)
            }
        }
        detail = fetchedDetail
        artistInfo = try? await client.getArtistInfo(id: resolvedID)
        // If the full discography was already crawled during this connection,
        // replay it from the cache instead of re-fetching every album's tracklist.
        if let cached = await app.cache?.cachedDiscography(for: artist.id) {
            allSongs = cached
            topSongs = Array(cached.sorted { ($0.playCount ?? 0) > ($1.playCount ?? 0) }.prefix(27))
            discographyTask?.cancel()
            discographyTask = nil
        } else if let serverTop = try? await client.getTopSongs(artist: detail?.name ?? artist.name, count: 27),
                   !serverTop.isEmpty {
            topSongs = serverTop
            discographyTask?.cancel()
            discographyTask = nil
        } else {
            // Fallback discography crawl if server does not provide top songs.
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
/// a plain "Исполнитель" fallback. Resolves the artist's distinct primary role
/// without concatenating multiple internal tags into a single text line.
enum ArtistRole {
    static func primaryRole(roles: [String]?, hasAlbums: Bool, songs: [SubsonicSong]) -> String {
        let normalized = roles?.map { $0.lowercased() } ?? []
        // If the artist released albums in the library, their primary role is Album Artist.
        if hasAlbums || normalized.contains("albumartist") {
            return "Исполнитель альбома".localized
        }
        // If the artist has no albums of their own in the library, but is a composer.
        if normalized.contains("composer") {
            return "Композитор".localized
        }
        // If the artist appears only as a featured performer on other artists' tracks.
        if normalized.contains("artist") {
            return "Приглашённый артист".localized
        }
        return "Исполнитель".localized
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
                    .transition(.opacity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(albums) { album in
                            Button {
                                app.openAlbumInLibrary(album)
                            } label: {
                                AlbumCard(album: album, width: 150, showsYear: true, reservesTitleLines: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                }
                .scrollClipDisabled()
                .transition(.opacity)
            }
        }
    }

    /// The discography as a compact adaptive grid (150pt cards), shown when the
    /// album section is expanded. Smaller than the Albums tab grid so more
    /// columns fit and cells hug the cards instead of leaving dead space.
    var albumsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            ForEach(albums) { album in
                Button {
                    app.openAlbumInLibrary(album)
                } label: {
                    AlbumCard(album: album, width: 150, showsYear: true, reservesTitleLines: true)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
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
        if !Task.isCancelled, !all.isEmpty {
            await app.cache?.cacheDiscography(all, for: artist.id)
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
                topSongs = Array(sorted.prefix(27))
            }
            start = end
            await Task.yield()
        }
    }
}