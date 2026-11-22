import SwiftUI
import NavidromeClient

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
            guard !app.isManualOffline, !app.isAuthError else { return }
            _ = await app.triggerImmediateProbe(silent: false)
        }
    }

    // MARK: - Albums Section (Expandable Carousel / Shelf)

    private var albumsShelf: some View {
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
                .help(albumsExpanded ? "Collapse Albums".localized : "Show albums in grid".localized)
                .accessibilityLabel(albumsExpanded ? "Collapse Albums".localized : "Show albums in grid".localized)

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
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)
            }
        }
        .animation(Motion.spring(Motion.expand), value: albumsExpanded)
    }

    private var songsShelf: some View {
        CompactSongsSection(
            title: "Songs".localized,
            titleFont: .title2.bold(),
            songs: songs,
            subtitle: { $0.artist }
        )
    }

    // MARK: - Artists Section (Circular Art Shelf)

    private var artistsShelf: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Artists".localized)
                .font(.title2.bold())

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
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

    private var playlistsShelf: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Playlists".localized)
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
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var emptyOfflineState: some View {
        ContentUnavailableView {
            Label(emptyStateTitle, systemImage: emptyStateIcon)
        } description: {
            Text(emptyStateDescription)
        } actions: {
            if app.isAuthError {
                Button("Sign In".localized) {
                    app.isAddingServer = true
                }
                .buttonStyle(.borderedProminent)
            } else if !app.isManualOffline && !app.serverConfig.effectiveForceOfflineMode {
                Button("Retry".localized) {
                    Task { _ = await app.triggerImmediateProbe(silent: false) }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .emptyStatePinnedToTop()
    }

    private var emptyStateTitle: String {
        switch app.offlineReason {
        case .authRequired: return "Authentication".localized
        case .noNetwork: return "No Network".localized
        case .serverUnreachable: return "Server Offline".localized
        case .manual, .none: return "No Saved Music".localized
        }
    }

    private var emptyStateIcon: String {
        switch app.offlineReason {
        case .authRequired: return "exclamationmark.triangle"
        case .noNetwork: return "wifi.slash"
        case .serverUnreachable: return "exclamationmark.icloud"
        case .manual, .none: return "arrow.down.circle"
        }
    }

    private var emptyStateDescription: String {
        if app.isAuthError {
            return "Authentication failed. Check your username and password.".localized
        }
        return "Songs and albums will appear here after you download them while online.".localized
    }
}
