import SwiftUI
import NavidromeClient

/// A dedicated Home view presented when the application is running in offline mode.
/// Uses established Klopydrome / Apple Music patterns: expandable album carousel (shelf <-> grid),
/// compact songs carousel/grid, circular artists, and playlist tiles.
struct OfflineHomeView: View {
    @Environment(AppState.self) private var app
    @State private var albumsExpanded = false
    @State private var cachedArtists: [Artist] = []

    private var albums: [SubsonicAlbum] { app.library.albums }
    private var songs: [SubsonicSong] { app.downloadedSongs }
    private var artists: [Artist] {
        if !cachedArtists.isEmpty { return cachedArtists }
        let fromIndexes = app.library.artistIndexes.flatMap { $0.artist ?? [] }
        if !fromIndexes.isEmpty { return fromIndexes }
        return app.offlineArtists(from: app.downloadedSongs)
    }
    private var playlists: [PlaylistSummary] { app.library.playlists }

    private var isAllEmpty: Bool {
        albums.isEmpty && songs.isEmpty && artists.isEmpty && playlists.isEmpty
    }

    private func reloadArtists() {
        let fromIndexes = app.library.artistIndexes.flatMap { $0.artist ?? [] }
        if !fromIndexes.isEmpty {
            cachedArtists = fromIndexes
        } else {
            cachedArtists = app.offlineArtists(from: app.downloadedSongs)
        }
    }

    var body: some View {
        ZStack {
            AMColor.background.ignoresSafeArea()

            if isAllEmpty {
                emptyOfflineState
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 28) {
                        if !albums.isEmpty {
                            albumsShelf
                        }

                        if !songs.isEmpty {
                            songsShelf
                        }

                        if !artists.isEmpty {
                            artistsShelf
                        }

                        if !playlists.isEmpty {
                            playlistsShelf
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                }
                .scrollClipDisabled()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            reloadArtists()
        }
        .onChange(of: app.downloadedSongs.count) { _, _ in
            reloadArtists()
        }
        .onChange(of: app.library.artistIndexes.count) { _, _ in
            reloadArtists()
        }
        .refreshable {
            _ = await app.reconnect()
        }
    }

    // MARK: - Albums Section (Expandable Carousel / Shelf)

    private var albumsShelf: some View {
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
                .help(albumsExpanded ? "Свернуть альбомы".localized : "Раскрыть альбомы сеткой".localized)
                .accessibilityLabel(albumsExpanded ? "Свернуть альбомы".localized : "Раскрыть альбомы сеткой".localized)

                Spacer()
            }

            if albumsExpanded {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 14)], spacing: 14) {
                    ForEach(albums) { album in
                        Button {
                            app.openAlbumInLibrary(album)
                        } label: {
                            AlbumCard(album: album, width: 165, showsYear: true, reservesTitleLines: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
                .transition(.opacity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 16) {
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
                .transition(.opacity)
            }
        }
    }

    // MARK: - Songs Section (Compact Carousel / 3x3 Expandable Grid)

    private var songsShelf: some View {
        CompactSongsSection(
            title: "Песни".localized,
            titleFont: .title2.bold(),
            songs: songs,
            subtitle: { $0.artist }
        )
    }

    // MARK: - Artists Section (Circular Art Shelf)

    private var artistsShelf: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Исполнители".localized)
                .font(.title2.bold())

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(artists) { artist in
                        Button {
                            app.openArtistInLibrary(artist)
                        } label: {
                            VStack(spacing: 6) {
                                CircularArtistArt(
                                    name: artist.name,
                                    imageURL: artist.artistImageUrl,
                                    coverArt: app.coverArtForArtist(artist),
                                    size: 80
                                )
                                Text(artist.name)
                                    .font(.caption)
                                    .lineLimit(2)
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
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()
        }
    }

    // MARK: - Playlists Section (Playlist Tiles Shelf)

    private var playlistsShelf: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Плейлисты".localized)
                .font(.title2.bold())

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(playlists) { playlist in
                        Button {
                            app.openPlaylist(playlist)
                        } label: {
                            PlaylistTile(playlist: playlist, width: 165)
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

    // MARK: - Empty State

    private var emptyOfflineState: some View {
        ContentUnavailableView {
            Label("Нет сохранённой музыки".localized, systemImage: "arrow.down.circle")
        } description: {
            Text("Песни и альбомы появятся здесь после того, как вы скачаете их в онлайн-режиме.".localized)
        } actions: {
            if !app.serverConfig.effectiveForceOfflineMode {
                Button("Подключиться к серверу".localized) {
                    Task { _ = await app.reconnect() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .emptyStatePinnedToTop()
    }
}
