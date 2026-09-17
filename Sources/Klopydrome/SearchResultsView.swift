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
                    "Ищите музыку".localized,
                    systemImage: "magnifyingglass",
                    description: Text("Введите запрос, чтобы найти исполнителей, альбомы и песни.".localized)
                )
                .emptyStatePinnedToTop()
            } else if isAllEmpty {
                ContentUnavailableView(
                    "Ничего не найдено".localized,
                    systemImage: "magnifyingglass",
                    description: Text("Попробуйте изменить запрос или параметры фильтра.".localized)
                )
                .emptyStatePinnedToTop()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        topResultsHero
                        if !albums.isEmpty {
                            albumSection
                        }
                        if !artists.isEmpty {
                            artistSection
                        }
                        if !matchingPlaylists.isEmpty {
                            playlistSection
                        }
                        if songs.count > 4 {
                            moreSongsSection
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

// MARK: - Search Results Sections
extension SearchResultsView {

    @ViewBuilder
    private var topResultsHero: some View {
        if let topArtist = artists.first, !songs.isEmpty {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Лучший результат".localized).font(.title3.bold())
                    Button {
                        app.openArtistInLibrary(topArtist)
                    } label: {
                        TopArtistCard(artist: topArtist)
                    }
                    .buttonStyle(.plain)
                }
                .frame(width: 220)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Песни".localized).font(.title3.bold())
                    topSongsList
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if !songs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Песни".localized).font(.title3.bold())
                topSongsList
            }
        }
    }

    private var topSongsList: some View {
        let currentID = app.player.currentSong?.id
        let topSongs = Array(songs.prefix(4))
        return LazyVStack(spacing: 0) {
            ForEach(Array(topSongs.enumerated()), id: \.element.id) { index, song in
                SongRow(song: song, index: index, showAlbum: true,
                        isCurrentOverride: currentID == song.id,
                        onPlay: { idx in app.play(songs, at: idx) })
            }
        }
    }

    private var moreSongsSection: some View {
        let currentID = app.player.currentSong?.id
        let remaining = Array(songs.dropFirst(4))
        return VStack(alignment: .leading, spacing: 10) {
            Text("Другие песни".localized).font(.title3.bold())
            LazyVStack(spacing: 0) {
                ForEach(Array(remaining.enumerated()), id: \.element.id) { index, song in
                    SongRow(song: song, index: index + 4, showAlbum: true,
                            isCurrentOverride: currentID == song.id,
                            onPlay: { idx in app.play(songs, at: idx) })
                }
            }
        }
    }

    private var albumSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Альбомы".localized).font(.title3.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
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
        }
    }

    private var artistSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Исполнители".localized).font(.title3.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(artists) { artist in
                        Button {
                            app.openArtistInLibrary(artist)
                        } label: {
                            VStack(spacing: 6) {
                                CircularArtistArt(name: artist.name, imageURL: artist.artistImageUrl, size: 80)
                                Text(artist.name)
                                    .font(.caption)
                                    .lineLimit(2)
                                    .frame(width: 80)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()
        }
    }

    private var playlistSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Плейлисты".localized).font(.title3.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(matchingPlaylists) { playlist in
                        Button {
                            app.openPlaylist(playlist)
                        } label: {
                            PlaylistTile(playlist: playlist)
                                .frame(width: 150)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()
        }
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
        albums = result?.albums ?? []
        songs = result?.songs ?? []
    }
}

private struct TopArtistCard: View {
    let artist: Artist
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CircularArtistArt(name: artist.name, imageURL: artist.artistImageUrl, size: 96)
            VStack(alignment: .leading, spacing: 2) {
                Text(artist.name)
                    .font(.headline)
                    .lineLimit(1)
                Text("Исполнитель".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 220, height: 180, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.08 : 0.04))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.15), value: hovering)
    }
}