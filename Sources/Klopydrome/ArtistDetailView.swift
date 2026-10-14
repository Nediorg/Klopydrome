import SwiftUI
import NavidromeClient

struct ArtistDetailView: View {
    let artist: Artist
    @Environment(AppState.self) var app

    @State var detail: ArtistDetail?
    @State private var loading = true
    @State var topSongs: [SubsonicSong]?
    @State private var loadingTopSongs = true
    /// Every song of the artist, fetched once by `load()` and reused by
    /// "Gather & Play" instead of issuing a duplicate request burst.
    @State var allSongs: [SubsonicSong] = []
    @State private var gatheringSongs = false
    @State private var artistInfo: ArtistInfoPayload?
    @State private var showInfoSheet = false

    /// Albums fetched concurrently at a time; keeps a big artist from issuing
    /// hundreds of simultaneous album requests to the server.
    let albumBatchSize = 8

    /// Sort chosen for the album shelf; defaults to release date.
    @State private var albumSort: ArtistAlbumSort = .release
    /// Albums this artist appears on without being the lead/album artist.
    @State var appearsOn: [SubsonicAlbum] = []
    /// Expands the album shelf into a full grid when true; the header chevron toggles it.
    @State private var albumsExpanded = false
    /// Sort direction for the album shelf/grid (descending = newest first by default).
    @State private var albumsDescending = true

    @State private var cachedAlbums: [SubsonicAlbum] = []
    @State private var cachedLatestRelease: SubsonicAlbum?

    var albums: [SubsonicAlbum] { cachedAlbums }
    private var latestReleaseCandidate: SubsonicAlbum? { cachedLatestRelease }

    private func updateCachedAlbums() {
        let source = detail?.album ?? []
        cachedAlbums = sortedAlbums(source, by: albumSort, descending: albumsDescending)
        cachedLatestRelease = source.max { lhs, rhs in
            let lhsYear = lhs.year ?? 0
            let rhsYear = rhs.year ?? 0
            if lhsYear != rhsYear { return lhsYear < rhsYear }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    /// Role label inferred from the OpenSubsonic `roles` tag when present,
    /// Identifying the artist's primary role (album artist vs composer vs guest).
    private var roleLabel: String? {
        ArtistRole.primaryRole(
            roles: displayDetail.roles,
            hasAlbums: !(albums.isEmpty && (displayDetail.albumCount ?? 0) == 0),
            songs: allSongs
        )
    }

    private var displayDetail: ArtistDetail {
        detail ?? ArtistDetail(
            id: artist.id,
            name: artist.name,
            coverArt: artist.artistImageUrl,
            albumCount: artist.albumCount,
            artistImageUrl: artist.artistImageUrl,
            starred: artist.starred
        )
    }

    var body: some View {
        Group {
            if detail != nil || loading {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        ArtistHeroBanner(
                            artist: artist,
                            detail: displayDetail,
                            roleLabel: roleLabel,
                            albums: albums,
                            allSongs: allSongs,
                            artistInfo: artistInfo,
                            gatheringSongs: gatheringSongs,
                            onPlay: { gatherAndPlay() },
                            onShowInfo: {
                                withAnimation(.snappy(duration: 0.2)) {
                                    showInfoSheet = true
                                }
                            }
                        )

                        VStack(alignment: .leading, spacing: 28) {
                            ArtistHeroRow(
                                artist: artist,
                                latest: latestReleaseCandidate,
                                top: topSongs,
                                isLoadingTop: loadingTopSongs
                            )
                            if !albums.isEmpty {
                                albumsShelf
                            } else if loading {
                                albumsShelfSkeleton
                            }
                            if !appearsOn.isEmpty {
                                appearsOnSection()
                            }
                            if let similar = artistInfo?.similarArtist, !similar.isEmpty {
                                similarArtistsSection(similar)
                            }
                        }
                        .padding(.horizontal, 28)
                        .padding(.bottom, 24)
                    }
                }
                .scrollClipDisabled()
            } else {
                ContentUnavailableView("Исполнитель недоступен", systemImage: "music.mic")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .inWindowModal(isPresented: $showInfoSheet) {
            ArtistInfoSheet(
                artist: artist,
                detail: displayDetail,
                roleLabel: roleLabel,
                albums: albums,
                allSongs: allSongs,
                artistInfo: artistInfo,
                onDismiss: {
                    showInfoSheet = false
                }
            )
        }
        .task(id: "\(artist.id)|\(app.isOfflineSession)") { await load() }
        .onChange(of: detail) { updateCachedAlbums() }
        .onChange(of: albumSort) { updateCachedAlbums() }
        .onChange(of: albumsDescending) { updateCachedAlbums() }
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
                            AlbumCard(album: album, width: 150, showsYear: false, reservesTitleLines: false)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
            }
            .scrollClipDisabled()
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func similarArtistsSection(_ similar: [Artist]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Похожие исполнители".localized)
                .font(.title2.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(similar) { artist in
                        Button {
                            app.openArtistInLibrary(artist)
                        } label: {
                            VStack(spacing: 6) {
                                CircularArtistArt(
                                    name: artist.name,
                                    imageURL: artist.artistImageUrl,
                                    coverArt: artist.coverArt ?? app.coverArtForArtist(artist),
                                    size: 80
                                )
                                Text(artist.name)
                                    .font(.caption)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .frame(width: 80, alignment: .top)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            ArtistContextMenuItems(artist: artist)
                        }
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
            }
            .scrollClipDisabled()
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Actions

    private func gatherAndPlay() {
        guard !gatheringSongs else { return }
        gatheringSongs = true
        Task {
            defer { gatheringSongs = false }
            if allSongs.isEmpty {
                allSongs = await allAlbumSongs()
            }
            if !allSongs.isEmpty { app.play(allSongs, at: 0) }
        }
    }

    private func resolveArtistID(client: SubsonicClient) async -> (id: String, detail: ArtistDetail?) {
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
        return (resolvedID, fetchedDetail)
    }

    private func load() async {
        loading = true
        defer { loading = false }

        if app.isOfflineSession || app.client == nil {
            loadOfflineArtist()
            loadingTopSongs = false
            return
        }

        // 1. Instant restore from SWR disk/memory cache
        if detail == nil, let cached = await app.cachedArtistDetail(for: artist.id) {
            detail = cached
            updateCachedAlbums()
        }

        guard let client = app.client else {
            loadingTopSongs = false
            return
        }

        let (resolvedID, fetchedDetail) = await resolveArtistID(client: client)
        if let fetchedDetail {
            withAnimation(.snappy(duration: 0.2)) {
                detail = fetchedDetail
            }
            await app.persistArtistDetail(fetchedDetail)
        }
        let name = detail?.name ?? artist.name

        // Fetch artist info and tracks concurrently
        async let infoTask: ArtistInfoPayload? = try? await client.getArtistInfo(id: resolvedID)
        async let tracksTask: Void = loadTracks(client: client, resolvedID: resolvedID, name: name)

        let (info, _) = await (infoTask, tracksTask)
        artistInfo = info

        if appearsOn.isEmpty {
            await loadAppearsOn(client: client)
        }
    }

    private func loadTracks(client: SubsonicClient, resolvedID: String, name: String) async {
        defer { loadingTopSongs = false }
        if !name.isEmpty,
           let nativeTop = try? await client.getTopSongs(artist: name, artistId: resolvedID, count: 27),
           !nativeTop.isEmpty {
            topSongs = nativeTop
            if allSongs.isEmpty { allSongs = nativeTop }
            return
        }

        if let cached = await app.cache?.cachedDiscography(for: artist.id) {
            allSongs = cached
            topSongs = Array(sortTopSongs(cached).prefix(27))
            return
        }

        if !name.isEmpty,
           let search = try? await client.search3(query: name, artistCount: 0, albumCount: 0, songCount: 500) {
            let (lead, guestAlbums) = processSearchSongs(search.songs, artistID: resolvedID, name: name)
            if !lead.isEmpty {
                allSongs = lead
                topSongs = Array(sortTopSongs(lead).prefix(27))
                await app.cache?.cacheDiscography(lead, for: artist.id)
            }
            if !guestAlbums.isEmpty && appearsOn.isEmpty {
                appearsOn = guestAlbums
            }
        }

        if topSongs == nil {
            topSongs = []
        }
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
                artist: song.albumArtist ?? song.artist,
                coverArt: song.coverArt,
                year: song.year)
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
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)
            }
        }
    }

    private var albumsShelfSkeleton: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Альбомы".localized)
                .font(.title2.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                albumSkeletonCards(forMask: false)
                    .shimmering()
                    .mask {
                        albumSkeletonCards(forMask: true)
                    }
            }
            .scrollClipDisabled()
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func albumSkeletonCards(forMask: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(0..<4, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(forMask ? Color.black : Color.primary.opacity(0.08))
                        .frame(width: 150, height: 150)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(forMask ? Color.black : Color.primary.opacity(0.08))
                        .frame(width: 100, height: 11)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(forMask ? Color.black : Color.primary.opacity(0.05))
                        .frame(width: 60, height: 9)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
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
}