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
    @State private var albumsExpanded = false
    @State private var loadError: String?

    private var isAllEmpty: Bool {
        artists.isEmpty && albums.isEmpty && songs.isEmpty && followedPlaylists.isEmpty
    }

    var body: some View {
        ZStack {
            AMColor.background.ignoresSafeArea()

            if let loadError {
                LibraryUnavailableView(title: "Failed to load".localized,
                                       systemImage: "wifi.exclamationmark",
                                       message: loadError,
                                       retry: { Task { await load() } })
                    .emptyStatePinnedToTop()
            } else if loading && isAllEmpty {
                favoritesSkeletonView
            } else if isAllEmpty {
                LibraryUnavailableView(title: "No Favorites".localized,
                                       systemImage: "star",
                                       message: "Star songs, albums and artists to see them here.".localized)
                    .emptyStatePinnedToTop()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        if !songs.isEmpty {
                            CompactSongsSection(
                                title: "Songs".localized,
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

    private var albumSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                albumsExpanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Text("Albums".localized)
                        .font(.title3.bold())
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(albumsExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(albumsExpanded ? "Collapse".localized : "Expand".localized)
            .accessibilityLabel(albumsExpanded ? "Collapse".localized : "Expand".localized)

            if albumsExpanded {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 16)], spacing: 16) {
                    ForEach(albums) { album in
                        Button {
                            app.openAlbumInLibrary(album)
                        } label: {
                            AlbumCard(album: album, width: 165)
                                .equatable()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
                .transition(.opacity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(albums) { album in
                            Button {
                                app.openAlbumInLibrary(album)
                            } label: {
                                AlbumCard(album: album)
                                    .equatable()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollClipDisabled()
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)
            }
        }
        .animation(Motion.spring(Motion.expand), value: albumsExpanded)
    }

    private var playlistSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Playlists".localized)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(followedPlaylists) { playlist in
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

    private var favoritesSkeletonView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader("Songs".localized)
                    SkeletonSongList(count: 3, showAlbum: true)
                }

                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader("Albums".localized)
                    SkeletonCardShelf(count: 4, cardSize: 150, isCircle: false, spacing: 16)
                }

                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader("Artists".localized)
                    SkeletonCardShelf(count: 5, cardSize: 90, isCircle: true, spacing: 16)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
        .scrollClipDisabled()
    }

    private func load() async {
        guard let client = app.client else { return }
        if isAllEmpty { loading = true }
        defer { loading = false }
        do {
            let result = try await client.getStarred2()
            loadError = nil
            withAnimation(.snappy(duration: 0.25)) {
                app.library.favoritesArtists = result.artists
                app.library.favoritesAlbums = result.albums
                app.library.favoritesSongs = result.songs
                app.library.favoritesLoaded = true
            }
            await app.persistFavoritesToDisk()
        } catch {
            if isAllEmpty { loadError = error.localizedDescription }
        }
        await app.refreshPlaylists()
    }
}