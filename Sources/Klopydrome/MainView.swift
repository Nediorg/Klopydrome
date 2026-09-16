import SwiftUI
import AppKit
import NavidromeClient

struct MainView: View {
    // Visible to MainView+Toolbar.swift (size gate: toolbar lives in an
    // extension there, so shared state can't stay private).
    @Environment(AppState.self) var app
    @AppStorage("debugShowPlayerState") private var debugShowPlayerState = false

    @State var showDownloads = false
    @State var isMiniPlayerVisible = false
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
        } detail: {
            DetailColumn(
                showDownloads: $showDownloads,
                isMiniPlayerVisible: isMiniPlayerVisible
            )
            // Detail-column limiter: with no floor the split divider can
            // squeeze the content to a sliver once the sidebar hits its
            // max (300), and then keep dragging the window itself below
            // the toolbar width. This floor stops both.
            .navigationSplitViewColumnWidth(
                min: LayoutMetrics.detailColumnMinWidth,
                ideal: 700,
                max: .infinity
            )
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar { }
        .background(AMColor.background)
        .overlay(alignment: .topTrailing) {
            if debugShowPlayerState {
                MiniPlayerDebugOverlay(app: app)
                    .allowsHitTesting(false)
                    .padding(.top, 60)
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
/// the top safe area inset of this column, matching Apple Music.
struct DetailColumn: View {
    @Environment(AppState.self) private var app
    @Binding var showDownloads: Bool
    var isMiniPlayerVisible: Bool

    var body: some View {
        DetailView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .trailing) {
                if app.queuePanelVisible {
                    PlayerPanelView()
                        .transition(.move(edge: .trailing))
                        .zIndex(2)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                PlayerHeaderBar(
                    showDownloads: $showDownloads,
                    isMiniPlayerVisible: isMiniPlayerVisible
                )
            }
            .ignoresSafeArea(edges: .top)
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

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("")
            .background(AMColor.background)
    }

    @ViewBuilder
    private var content: some View {
        if let current = app.nav.history.last {
            switch current {
            case .album(let album):
                AlbumDetailView(album: album)
            case .playlist(let playlist):
                PlaylistDetailView(playlist: playlist)
            case .smartPlaylist(let smart):
                SmartPlaylistDetailView(playlist: smart)
            case .artist(let artist):
                ArtistDetailView(artist: artist)
            case .song(let song):
                SongDetailView(song: song)
            }
        } else if let playlist = app.nav.selectedPlaylist {
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
    var onHover: ((Bool) -> Void)?
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
                content(width: width)
                    .allowsHitTesting(false)

                if isLCDHovered {
                    HStack {
                        Text(app.player.formattedCurrentTime())
                        Spacer(minLength: 0)
                        Text(app.player.formattedRemainingTime())
                    }
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(AMColor.secondaryText)
                    .padding(.leading, 2)
                    .padding(.trailing, 4)
                    .padding(.bottom, trackHeight)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }

                Color.clear
                    .frame(width: width, height: hitHeight)
                    .contentShape(Rectangle())
                    .overlay {
                        InteractiveSliderTrack(
                            onDragStarted: {
                                guard trackDuration > 0, width > 0 else { return }
                                if dragProgress == nil {
                                    app.player.beginScrub()
                                }
                            },
                            onDragChanged: { ratio in
                                guard trackDuration > 0, width > 0 else { return }
                                dragProgress = ratio
                                app.player.scrub(to: Double(ratio) * trackDuration)
                            },
                            onDragEnded: { ratio in
                                guard trackDuration > 0, width > 0 else { return }
                                app.player.endScrub(at: Double(ratio) * trackDuration)
                                dragProgress = nil
                            },
                            onHoverChanged: { hovering in
                                onHover?(hovering)
                            },
                            calculateProgress: { point, size in
                                scrubberProgress(pointX: point.x, width: size.width)
                            }
                        )
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Позиция воспроизведения")
                    .accessibilityValue(app.player.formattedCurrentTime())
                    .accessibilityAdjustableAction { direction in
                        let step = direction == .increment ? 10.0 : -10.0
                        app.player.seek(to: min(max(app.player.currentTime + step, 0), app.player.trackDuration))
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

    /// The first 5 pt of the track are clamped to 0:00, making rewinding
    /// to the very beginning of the track effortless on the first try.
    private func scrubberProgress(pointX: CGFloat, width: CGFloat) -> CGFloat {
        let deadzone: CGFloat = 5.0
        guard width > deadzone else { return 0 }
        if pointX <= deadzone { return 0 }
        let effectiveX = pointX - deadzone
        let effectiveWidth = width - deadzone
        return min(max(effectiveX / effectiveWidth, 0), 1)
    }
}
