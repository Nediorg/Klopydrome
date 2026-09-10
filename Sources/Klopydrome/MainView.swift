import SwiftUI
import AppKit
import NavidromeClient

struct MainView: View {
    // Visible to MainView+Toolbar.swift (size gate: toolbar lives in an
    // extension there, so shared state can't stay private).
    @Environment(AppState.self) var app
    @AppStorage("debugShowPlayerState") private var debugShowPlayerState = false

    @State var path = NavigationPath()
    @State var showDownloads = false
    @State var isMiniPlayerVisible = false
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
        } detail: {
            DetailColumn(path: $path)
                // Detail-column limiter: with no floor the split divider can
                // squeeze the content to a sliver once the sidebar hits its
                // max (300), and then keep dragging the window itself below
                // the toolbar width. This floor stops both.
                .navigationSplitViewColumnWidth(
                    min: LayoutMetrics.detailColumnMinWidth,
                    ideal: 640,
                    max: .infinity
                )
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar { playerToolbar }
        .toolbarBackground(.ultraThinMaterial, for: .windowToolbar)
        // The lyrics/queue panel is a FLOATING overlay over the whole window
        // (Apple Music-style): it slides in from the trailing edge on top of
        // the sidebar and content, so the Home shelves show through the blur.
        .overlay(alignment: .trailing) {
            if app.queuePanelVisible {
                PlayerPanelView()
                    .transition(.move(edge: .trailing))
                    .zIndex(2)
            }
        }
        .background(AMColor.background)
        .overlay(alignment: .topTrailing) {
            if debugShowPlayerState {
                MiniPlayerDebugOverlay(app: app)
                    .allowsHitTesting(false)
                    .padding(.top, 8)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .miniPlayerDidOpen)) { _ in
            isMiniPlayerVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .miniPlayerDidClose)) { _ in
            isMiniPlayerVisible = false
        }
        .sheet(isPresented: Binding(
            get: { app.isCreatingPlaylist },
            set: { app.isCreatingPlaylist = $0 }
        )) {
            CreatePlaylistModal(songs: app.creatingPlaylistSongs)
        }
        .sheet(item: Binding(
            get: { app.shareTarget },
            set: { app.shareTarget = $0 }
        )) { target in
            ShareSheet(target: target)
        }
    }
}

// MARK: - Detail column

/// The right-hand column: the navigable content region. The player bar lives in
/// the real window toolbar and the lyrics/queue panel floats as an overlay over
/// the whole window (see `MainView`).
struct DetailColumn: View {
    @Environment(AppState.self) private var app
    @Binding var path: NavigationPath

    var body: some View {
        DetailView(path: $path)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AMColor.background)
            .onKeyPress(.escape) {
                if app.queuePanelVisible {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        app.queuePanelVisible = false
                    }
                    return .handled
                }
                return .ignored
            }
    }
}

struct DetailView: View {
    @Environment(AppState.self) private var app
    @Binding var path: NavigationPath

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationDestination(for: SubsonicAlbum.self) { AlbumDetailView(album: $0) }
            .navigationDestination(for: Artist.self) { ArtistDetailView(artist: $0) }
            .navigationDestination(for: PlaylistSummary.self) { PlaylistDetailView(playlist: $0) }
            .navigationDestination(for: SubsonicSong.self) { SongDetailView(song: $0) }
            .navigationBarBackButtonHidden(true)
        }
        .navigationTitle("")
        .background(AMColor.background)
        // Every sidebar selection (via navVersion) pops the navigation stack,
        // so clicking a tab always returns to that tab's root — even a
        // sub-page like an album card is open, and even when the clicked item
        // was already selected.
        .onChange(of: app.nav.navVersion) { _, _ in
            path = NavigationPath()
        }
        .onChange(of: app.nav.pendingAlbum) { _, album in
            guard let album else { return }
            path = NavigationPath()
            path.append(album)
            app.nav.pendingAlbum = nil
        }
        .onChange(of: app.nav.pendingSong) { _, song in
            guard let song else { return }
            path = NavigationPath()
            path.append(song)
            app.nav.pendingSong = nil
        }
        .onChange(of: app.nav.pendingArtist) { _, artist in
            guard let artist else { return }
            path = NavigationPath()
            path.append(artist)
            app.nav.pendingArtist = nil
        }
    }

    @ViewBuilder
    private var content: some View {
        if let playlist = app.nav.selectedPlaylist {
            PlaylistDetailView(playlist: playlist)
        } else {
            switch app.nav.selected {
            case .home: HomeView()
            case .playlists: PlaylistsView()
            case .recentlyAdded: AlbumGridView(config: .recentlyAdded)
            case .songs: SongsView()
            case .artists: ArtistsView()
            case .albums: AlbumGridView(config: .albums)
            case .favorites: FavoritesView()
            case .search: SearchResultsView(query: app.nav.searchQuery.trimmingCharacters(in: .whitespaces))
            }
        }
    }
}

/// Minimalist progress strip for the toolbar player. A thin capsule track with
/// the current position filled; drag to seek. Hidden until the player bar is
/// hovered. Wrapped in a Button so the toolbar treats it as an interactive
/// control — a bare DragGesture in a toolbar is captured by the window-drag
/// region and would move the window instead of seeking.
struct MinimalScrubber: View {
    @Environment(AppState.self) private var app

    /// Hover keeps the track readable without turning the LCD into a second player bar.
    let isLCDHovered: Bool
    private var trackHeight: CGFloat { isLCDHovered ? 5 : 3 }
    private var hitHeight: CGFloat { isLCDHovered ? 18 : 12 }

    /// Progress preview while the user drags; nil uses the live player time.
    @State private var dragProgress: CGFloat?

    /// Sweep shows only while the player is actually loading/stalled, never during
/// plain playback (background caching ahead is not "loading").
    private var isLoading: Bool {
        app.player.isBuffering || app.player.isLoading
    }

    private var trackDuration: Double { app.player.trackDuration }

    private var trackProgress: CGFloat {
        guard trackDuration > 0 else { return 0 }
        if let dragProgress { return dragProgress }
        return CGFloat(min(max(app.player.currentTime / trackDuration, 0), 1))
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .bottom) {
                Color.clear
                Button(action: {}) {
                    content(width: width)
                }
                .buttonStyle(.plain)
                // The visual track stays compact, while the bottom-only hit zone is
                // large enough to scrub reliably without covering top LCD controls.
                .frame(width: width, height: hitHeight, alignment: .bottom)
                .contentShape(Rectangle())
                .simultaneousGesture(drag(width: width))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Позиция воспроизведения")
                .accessibilityValue(app.player.formattedCurrentTime())
                .accessibilityAdjustableAction { direction in
                    let step = direction == .increment ? 10.0 : -10.0
                    app.player.seek(to: min(max(app.player.currentTime + step, 0), app.player.trackDuration))
                }

                if isLCDHovered {
                    HStack {
                        Text(app.player.formattedCurrentTime())
                        Spacer(minLength: 0)
                        Text(app.player.formattedRemainingTime())
                    }
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(AMColor.secondaryText)
                    .padding(.horizontal, 4)
                    .padding(.bottom, trackHeight)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
        }
    }

    private func content(width: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle()
                .fill(Color.primary.opacity(isLCDHovered ? 0.20 : 0.13))
                .frame(height: trackHeight)
                .overlay(alignment: .center) {
                    Rectangle()
                        .stroke(Color.primary.opacity(0.18), lineWidth: 1)
                }
            if isLoading {
                SweepBar(width: width, trackHeight: trackHeight)
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(isLCDHovered ? 0.85 : 0.65))
                    .frame(height: trackHeight)
                    .scaleEffect(x: trackProgress, anchor: .leading)
                marker(width: width)
            }
        }
        .frame(width: width, height: trackHeight)
        .clipped()
    }

    /// Playback marker pinned to the bottom; taller and wider than the track
    /// so it's easy to grab while scrubbing.
    private func marker(width: CGFloat) -> some View {
        Rectangle()
            .fill(Color.secondary.opacity(isLCDHovered ? 0.90 : 0.65))
            .overlay {
                Rectangle()
                    .stroke(Color.primary.opacity(0.32), lineWidth: 1)
            }
            .frame(width: isLCDHovered ? 5 : 4,
                   height: trackHeight + (isLCDHovered ? 6 : 4))
            .opacity(isLCDHovered ? 1 : 0)
            .offset(x: trackProgress * width - (isLCDHovered ? 2.5 : 2))
    }

    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard trackDuration > 0, width > 0 else { return }
                let ratio = min(max(value.location.x / width, 0), 1)
                dragProgress = ratio
                app.player.beginScrub()
                app.player.scrub(to: ratio * trackDuration)
            }
            .onEnded { _ in
                guard let dragProgress, trackDuration > 0 else { return }
                app.player.endScrub(at: dragProgress * trackDuration)
                self.dragProgress = nil
            }
    }
}
