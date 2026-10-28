import SwiftUI
import NavidromeClient

struct SearchResultsView: View {
    let query: String
    @Environment(AppState.self) private var app

    @State private var artists: [Artist] = []
    @State private var albums: [SubsonicAlbum] = []
    @State private var songs: [SubsonicSong] = []
    @State private var loading = true

    private var matchingPlaylists: [PlaylistSummary] {
        guard !query.isEmpty else { return [] }
        return app.library.playlists.filter {
            $0.displayName.localizedCaseInsensitiveContains(query) ||
            ($0.comment?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var isAllEmpty: Bool {
        artists.isEmpty && albums.isEmpty && songs.isEmpty && matchingPlaylists.isEmpty
    }

    var body: some View {
        ZStack {
            AMColor.background.ignoresSafeArea()

            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if query.isEmpty {
                ContentUnavailableView(
                    "Find music".localized,
                    systemImage: "magnifyingglass",
                    description: Text("Enter a search to find artists, albums, and songs.".localized)
                )
                .emptyStatePinnedToTop()
            } else if isAllEmpty {
                ContentUnavailableView(
                    "Nothing Found".localized,
                    systemImage: "magnifyingglass",
                    description: Text("Try changing the query or filter settings.".localized)
                )
                .emptyStatePinnedToTop()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        if !topResultItems.isEmpty {
                            topResultsSection
                        }
                        if !songs.isEmpty {
                            songsSection
                        }
                        if !albums.isEmpty {
                            albumSection
                        }
                        if !artists.isEmpty {
                            artistSection
                        }
                        if !matchingPlaylists.isEmpty {
                            playlistSection
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                }
                .scrollClipDisabled()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: "\(app.nav.navVersion)|\(query)") { await load() }
    }
}

private enum SearchTopResultItem: Identifiable {
    case artist(Artist)
    case album(SubsonicAlbum)
    case playlist(PlaylistSummary)
    case song(SubsonicSong)

    var id: String {
        switch self {
        case .artist(let artist): return "a-\(artist.id)"
        case .album(let album): return "al-\(album.id)"
        case .playlist(let playlist): return "p-\(playlist.id)"
        case .song(let song): return "s-\(song.id)"
        }
    }
}

extension SearchResultsView {

    private var topResultItems: [SearchTopResultItem] {
        var items: [SearchTopResultItem] = []

        if let artist = artists.first {
            items.append(.artist(artist))
        }
        if let album = albums.first {
            items.append(.album(album))
        }
        if let playlist = matchingPlaylists.first {
            items.append(.playlist(playlist))
        }

        for song in songs where items.count < 8 {
            items.append(.song(song))
        }

        if items.count < 8 {
            for album in albums.dropFirst() where items.count < 8 {
                items.append(.album(album))
            }
        }

        if items.count < 8 {
            for artist in artists.dropFirst() where items.count < 8 {
                items.append(.artist(artist))
            }
        }

        if items.count < 8 {
            for playlist in matchingPlaylists.dropFirst() where items.count < 8 {
                items.append(.playlist(playlist))
            }
        }

        return items
    }

    private var topResultsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Top Results".localized)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                spacing: 8
            ) {
                ForEach(topResultItems) { item in
                    switch item {
                    case .artist(let artist):
                        ArtistPillCard(artist: artist) {
                            app.openArtistInLibrary(artist)
                        }
                    case .album(let album):
                        AlbumPillCard(album: album) {
                            app.openAlbumInLibrary(album)
                        }
                    case .playlist(let playlist):
                        PlaylistPillCard(playlist: playlist) {
                            app.openPlaylist(playlist)
                        }
                    case .song(let song):
                        SongPillCard(
                            song: song,
                            isCurrent: app.player.currentSong?.id == song.id
                        ) {
                            if let idx = songs.firstIndex(where: { $0.id == song.id }) {
                                app.play(songs, at: idx)
                            } else {
                                app.play([song], at: 0)
                            }
                        }
                    }
                }
            }
        }
    }
}

extension SearchResultsView {
    private var songsSection: some View {
        CompactSongsSection(
            title: "Songs".localized,
            titleFont: .title3.bold(),
            songs: songs,
            subtitle: { $0.artist }
        )
    }
}

// MARK: - Album / Artist / Playlist horizontal shelves
extension SearchResultsView {

    private var albumSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Albums".localized)
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
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var artistSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Artists".localized)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(artists) { artist in
                        ArtistTile(artist: artist)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var playlistSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Playlists".localized)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(matchingPlaylists) { playlist in
                        Button {
                            app.openPlaylist(playlist)
                        } label: {
                            PlaylistTile(playlist: playlist, width: 165)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Helpers
extension SearchResultsView {

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3.bold())
    }

    private func load() async {
        loading = true
        defer {
            if !Task.isCancelled { loading = false }
        }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }

        if app.client == nil || app.isOfflineSession {
            let lower = query.lowercased()
            songs = app.library.songs.filter {
                $0.displayTitle.lowercased().contains(lower) ||
                ($0.artist?.lowercased().contains(lower) ?? false) ||
                ($0.album?.lowercased().contains(lower) ?? false)
            }
            albums = app.library.albums.filter {
                $0.displayName.lowercased().contains(lower) ||
                ($0.artist?.lowercased().contains(lower) ?? false)
            }
            artists = []
            return
        }

        guard let client = app.client, !query.isEmpty else { return }
        let result = try? await client.search3(query: query)
        guard !Task.isCancelled else { return }
        artists = result?.artists ?? []
        albums  = result?.albums  ?? []
        songs   = result?.songs   ?? []
    }
}