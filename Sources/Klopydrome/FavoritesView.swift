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
                favoritesSkeletonView
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
                HStack(alignment: .top, spacing: 16) {
                    ForEach(artists) { artist in
                        Button {
                            app.openArtistInLibrary(artist)
                        } label: {
                            VStack(spacing: 6) {
                                CircularArtistArt(name: artist.name, imageURL: artist.artistImageUrl, size: 80)
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

    private var albumSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(Motion.spring(Motion.expand)) {
                    albumsExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Альбомы".localized)
                        .font(.title3.bold())
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(albumsExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(albumsExpanded ? "Свернуть".localized : "Раскрыть".localized)
            .accessibilityLabel(albumsExpanded ? "Свернуть".localized : "Раскрыть".localized)

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
                .transition(.opacity)
            }
        }
    }

    private var playlistSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Плейлисты".localized)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(followedPlaylists) { playlist in
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

    private var favoritesSkeletonView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // 1. Songs section skeleton (3 rows)
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader("Песни".localized)
                    songSkeletonRows(forMask: false)
                        .shimmering()
                        .mask {
                            songSkeletonRows(forMask: true)
                        }
                }

                // 2. Albums section skeleton
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader("Альбомы".localized)
                    ScrollView(.horizontal, showsIndicators: false) {
                        albumSkeletonCards(forMask: false)
                            .shimmering()
                            .mask {
                                albumSkeletonCards(forMask: true)
                            }
                    }
                    .scrollClipDisabled()
                }

                // 3. Artists section skeleton
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader("Исполнители".localized)
                    ScrollView(.horizontal, showsIndicators: false) {
                        artistSkeletonCards(forMask: false)
                            .shimmering()
                            .mask {
                                artistSkeletonCards(forMask: true)
                            }
                    }
                    .scrollClipDisabled()
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
        .scrollClipDisabled()
    }

    private func songSkeletonRows(forMask: Bool) -> some View {
        VStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(forMask ? Color.black : Color.primary.opacity(0.08))
                        .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(forMask ? Color.black : Color.primary.opacity(0.08))
                            .frame(width: 140, height: 12)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(forMask ? Color.black : Color.primary.opacity(0.05))
                            .frame(width: 90, height: 10)
                    }
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
    }

    private func albumSkeletonCards(forMask: Bool) -> some View {
        HStack(spacing: 16) {
            ForEach(0..<4, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(forMask ? Color.black : Color.primary.opacity(0.08))
                        .frame(width: 150, height: 150)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(forMask ? Color.black : Color.primary.opacity(0.08))
                        .frame(width: 110, height: 12)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(forMask ? Color.black : Color.primary.opacity(0.05))
                        .frame(width: 70, height: 10)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func artistSkeletonCards(forMask: Bool) -> some View {
        HStack(spacing: 16) {
            ForEach(0..<5, id: \.self) { _ in
                VStack(spacing: 8) {
                    Circle()
                        .fill(forMask ? Color.black : Color.primary.opacity(0.08))
                        .frame(width: 90, height: 90)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(forMask ? Color.black : Color.primary.opacity(0.08))
                        .frame(width: 70, height: 11)
                }
            }
        }
        .padding(.vertical, 4)
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
        // Ensure the playlist list backing the "followed" section is fresh.
        await app.refreshPlaylists()
    }
}