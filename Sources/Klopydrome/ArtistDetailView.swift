import SwiftUI
import NavidromeClient

struct ArtistDetailView: View {
    let artist: Artist
    @Environment(AppState.self) var app

    @State var detail: ArtistDetail?
    @State private var loading = true
    @State var topSongs: [SubsonicSong]?
    @State private var loadingTopSongs = true
    @State var allSongs: [SubsonicSong] = []
    @State private var gatheringSongs = false
    @State private var artistInfo: ArtistInfoPayload?
    @State private var showInfoSheet = false

    let albumBatchSize = 8

    @State private var albumSort: ArtistAlbumSort = .release
    @State var appearsOn: [SubsonicAlbum] = []
    @State private var hasSearchedAppearsOn = false
    @State private var albumsExpanded = false
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
                ContentUnavailableView("Artist unavailable".localized, systemImage: "music.mic")
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
                Text("Appears on".localized)
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
            Text("Similar Artists".localized)
                .font(.title2.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(similar) { artist in
                        ArtistTile(artist: artist)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
            }
            .scrollClipDisabled()
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func gatherAndPlay() {
        guard !gatheringSongs else { return }
        gatheringSongs = true
        Task {
            defer { gatheringSongs = false }
            if allSongs.isEmpty {
                allSongs = await allAlbumSongs()
            }
            let toPlay = !allSongs.isEmpty ? allSongs : (topSongs ?? [])
            if !toPlay.isEmpty { app.play(toPlay, at: 0) }
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

        async let infoTask: ArtistInfoPayload? = try? await client.getArtistInfo(id: resolvedID)
        async let tracksTask: Void = loadTracks(client: client, resolvedID: resolvedID, name: name)

        let (info, _) = await (infoTask, tracksTask)
        artistInfo = info

        if appearsOn.isEmpty && !hasSearchedAppearsOn {
            await loadAppearsOn(client: client)
        }
    }

    private func loadTracks(client: SubsonicClient, resolvedID: String, name: String) async {
        defer { loadingTopSongs = false }
        if let cached = await app.cache?.cachedDiscography(for: artist.id), !cached.isEmpty {
            allSongs = cached
        }

        if !name.isEmpty,
           let nativeTop = try? await client.getTopSongs(artist: name, artistId: resolvedID, count: 27),
           !nativeTop.isEmpty {
            topSongs = nativeTop
            return
        }

        if !allSongs.isEmpty {
            topSongs = Array(sortTopSongs(allSongs).prefix(27))
            return
        }

        if !name.isEmpty,
           let search = try? await client.search3(query: name, artistCount: 0, albumCount: 0, songCount: 500) {
            hasSearchedAppearsOn = true
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

    private func loadAppearsOn(client: SubsonicClient) async {
        guard !hasSearchedAppearsOn else { return }
        hasSearchedAppearsOn = true
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

enum ArtistRole {
    static func primaryRole(roles: [String]?, hasAlbums: Bool, songs: [SubsonicSong]) -> String {
        let normalized = roles?.map { $0.lowercased() } ?? []
        if hasAlbums || normalized.contains("albumartist") {
            return "Album artist".localized
        }
        if normalized.contains("composer") {
            return "Composer".localized
        }
        if normalized.contains("artist") {
            return "Featured Artist".localized
        }
        return "Artist".localized
    }
}

private extension ArtistDetailView {
    var albumsShelf: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Button {
                    albumsExpanded.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Text("Albums".localized)
                            .font(.title2.bold())
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(albumsExpanded ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help((albumsExpanded ? "Collapse Albums" : "Show albums in grid").localized)
                .accessibilityLabel((albumsExpanded ? "Collapse Albums" : "Show albums in grid").localized)
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
        .animation(Motion.spring(Motion.expand), value: albumsExpanded)
    }

    private var albumsShelfSkeleton: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Albums".localized)
                .font(.title2.bold())
            SkeletonCardShelf(count: 4, cardSize: 150, isCircle: false, spacing: 12)
        }
    }

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