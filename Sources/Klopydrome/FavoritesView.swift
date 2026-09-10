import SwiftUI
import NavidromeClient

struct FavoritesView: View {
    @Environment(AppState.self) private var app

    private var artists: [Artist] { app.library.favoritesArtists }
    private var albums: [SubsonicAlbum] { app.library.favoritesAlbums }
    private var songs: [SubsonicSong] { app.library.favoritesSongs }
    private var followedPlaylists: [PlaylistSummary] {
        app.library.playlists.filter { app.isFollowed($0) }
    }
    @State private var loading = true
    /// Set when the favorites fetch fails, so an error renders with retry
    /// instead of a misleading "Нет избранного".
    @State private var loadError: String?

    var body: some View {
        Group {
            if let loadError {
                LibraryUnavailableView(title: "Не удалось загрузить",
                                       systemImage: "wifi.exclamationmark",
                                       message: loadError,
                                       retry: { Task { await load() } })
                    .emptyStatePinnedToTop()
            } else if loading && isAllEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isAllEmpty {
                LibraryUnavailableView(title: "Нет избранного",
                                       systemImage: "heart",
                                       message: "Отмечайте песни, альбомы и исполнителей звёздочкой, "
                                                + "чтобы они появились здесь.")
                    .emptyStatePinnedToTop()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        if !followedPlaylists.isEmpty { followedPlaylistSection }
                        if !artists.isEmpty { artistSection }
                        if !albums.isEmpty { albumSection }
                        if !songs.isEmpty { songSection }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                }
                .scrollClipDisabled()
            }
        }
        .task { await loadIfNeeded() }
        .refreshable { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .foregroundRefreshRequested)) { _ in
            if loadError != nil {
                Task { await load() }
            }
        }
    }

    /// Fetches starred content only when it has never been loaded, so a revisit
    /// to the tab is instant. Pull-to-refresh still forces a full reload.
    private func loadIfNeeded() async {
        guard !app.library.favoritesLoaded else { return }
        await load()
    }

    private var isAllEmpty: Bool { artists.isEmpty && albums.isEmpty && songs.isEmpty }

    private var followedPlaylistSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Плейлисты в избранном".localized).font(.title2.bold())
            VStack(spacing: 0) {
                ForEach(Array(followedPlaylists.enumerated()), id: \.element.id) { idx, playlist in
                    HStack {
                        NavigationLink(value: playlist) {
                            HStack(spacing: 8) {
                                Image(systemName: "music.note.list")
                                    .foregroundStyle(.secondary)
                                Text(playlist.displayName)
                                Spacer()
                                if let count = playlist.songCount {
                                    Text("\(count) \(Pluralized.track(count))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        Button {
                            withAnimation(.snappy(duration: 0.15)) {
                                app.toggleFollow(playlist)
                            }
                        } label: {
                            Image(systemName: "heart.slash")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Убрать из избранного")
                        .accessibilityLabel("Убрать плейлист из избранного")
                    }
                    .padding(.vertical, 4)
                    if idx < followedPlaylists.count - 1 { Divider().opacity(0.3) }
                }
            }
        }
    }

    private var artistSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Исполнители".localized).font(.title2.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(artists) { artist in
                        NavigationLink(value: artist) {
                            VStack(spacing: 6) {
                                CircularArtistArt(name: artist.name, imageURL: artist.artistImageUrl, size: 90)
                                Text(artist.name).font(.caption).lineLimit(2).frame(width: 90)
                            }
                            .contentShape(Rectangle())
                            .hoverScale(1.05)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
            }
            .scrollClipDisabled()
        }
    }

    private var albumSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Альбомы".localized).font(.title2.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(albums) { album in
                        NavigationLink(value: album) { AlbumCard(album: album) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
            }
            .scrollClipDisabled()
        }
    }

    private var songSection: some View {
        let currentID = app.player.currentSong?.id
        return VStack(alignment: .leading, spacing: 8) {
            Text("Песни".localized).font(.title2.bold())
            // Lazy: favorites can hold hundreds of songs, and a plain VStack
            // materializes every SongRow (hover tracking + stars) up front.
            LazyVStack(spacing: 0) {
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    SongRow(song: song, index: index, showAlbum: true,
                            isCurrentOverride: currentID == song.id,
                            onPlay: { idx in app.play(songs, at: idx) })
                    if index < songs.count - 1 { Divider().opacity(0.3) }
                }
            }
        }
    }

    private func load() async {
        guard let client = app.client else { return }
        if isAllEmpty { loading = true }
        defer { loading = false }
        do {
            let result = try await client.getStarred2()
            loadError = nil
            app.library.favoritesArtists = result.artists
            app.library.favoritesAlbums = result.albums
            app.library.favoritesSongs = result.songs
            app.library.favoritesLoaded = true
        } catch {
            if isAllEmpty { loadError = error.localizedDescription }
        }
        // Ensure the playlist list backing the "followed" section is fresh.
        await app.refreshPlaylists()
    }
}