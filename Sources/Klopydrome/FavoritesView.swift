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

    private var isAllEmpty: Bool {
        artists.isEmpty && albums.isEmpty && songs.isEmpty && followedPlaylists.isEmpty
    }

    var body: some View {
        ZStack {
            AMColor.background.ignoresSafeArea()

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
                                       systemImage: "star",
                                       message: "Отмечайте песни, альбомы и исполнителей звёздочкой, "
                                                + "чтобы они появились здесь.")
                    .emptyStatePinnedToTop()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        if !songs.isEmpty {
                            CompactSongsSection(
                                title: "Песни".localized,
                                titleFont: .title3.bold(),
                                songs: songs,
                                subtitle: { $0.artist }
                            )
                        }
                        if !albums.isEmpty {
                            albumSection
                        }
                        if !artists.isEmpty {
                            artistSection
                        }
                        if !followedPlaylists.isEmpty {
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

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3.bold())
    }

    private var artistSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Исполнители".localized)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
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
                        .contextMenu {
                            ArtistContextMenuItems(artist: artist)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()
        }
    }

    private var albumSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Альбомы".localized)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
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

    private var playlistSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Плейлисты".localized)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(followedPlaylists) { playlist in
                        Button {
                            app.openPlaylist(playlist)
                        } label: {
                            PlaylistTile(playlist: playlist)
                                .frame(width: 150)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            PlaylistContextMenuItems(playlist: playlist)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()
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