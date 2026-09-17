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
                        if !artists.isEmpty || !songs.isEmpty {
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

// MARK: - Top Results Section
extension SearchResultsView {

    /// Up to 8 cards in a 4-column grid: artist first (if any), then top songs.
    private var topResultsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Лучшие результаты".localized)

            let topSongs = Array(songs.prefix(7))
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                spacing: 8
            ) {
                if let artist = artists.first {
                    TopResultArtistCard(artist: artist) {
                        app.openArtistInLibrary(artist)
                    }
                }
                ForEach(topSongs) { song in
                    TopResultSongCard(
                        song: song,
                        isCurrent: app.player.currentSong?.id == song.id
                    ) {
                        if let idx = songs.firstIndex(where: { $0.id == song.id }) {
                            app.play(songs, at: idx)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Songs Section
extension SearchResultsView {
    private var songsSection: some View {
        CompactSongsSection(
            title: "Песни".localized,
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

    private var playlistSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Плейлисты".localized)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(matchingPlaylists) { playlist in
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

// MARK: - Top Result Cards

/// Artist card for the Top Results grid — circular avatar + name + chevron.
private struct TopResultArtistCard: View {
    let artist: Artist
    let onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                CircularArtistArt(name: artist.name, imageURL: artist.artistImageUrl, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(artist.name)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text("Исполнитель".localized)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.09 : 0.05))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.12), value: hovering)
        .contextMenu { ArtistContextMenuItems(artist: artist) }
    }
}

/// Song card for the Top Results grid — small thumbnail + title/type + ellipsis.
private struct TopResultSongCard: View {
    let song: SubsonicSong
    let isCurrent: Bool
    let onPlay: () -> Void
    @Environment(AppState.self) private var app
    @State private var hovering = false

    private var isStarred: Bool { app.isStarred(song) }

    var body: some View {
        HStack(spacing: 8) {
            CoverArtView(coverArt: song.coverArt, size: 40, cornerRadius: 4)

            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.displayTitle)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .foregroundStyle(isCurrent ? AMColor.accent : .primary)
                    Text(subtitleText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Button {
                    app.toggleStar(song)
                } label: {
                    Image(systemName: isStarred ? "star.fill" : "star")
                        .font(.system(size: 11))
                        .foregroundStyle(isStarred ? AMColor.accent : Color.secondary)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isStarred ? "Убрать из избранного".localized : "В избранное".localized)
                .opacity(isStarred ? 1 : (hovering ? 1 : 0))
                .allowsHitTesting(hovering || isStarred)

                Menu {
                    SongActionItems(app: app, song: song, onPlay: onPlay)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .opacity(hovering ? 1 : 0)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.09 : 0.05))
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onPlay() }
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.12), value: hovering)
        .contextMenu {
            SongActionItems(app: app, song: song, onPlay: onPlay)
        }
    }

    private var subtitleText: String {
        let type = "Песня".localized
        if let artist = song.artist, !artist.isEmpty {
            return "\(type) · \(artist)"
        }
        return type
    }
}