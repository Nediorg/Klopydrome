import SwiftUI
import NavidromeClient
import AppKit

// MARK: - Player LCD (extracted from MainView)

/// The LCD block of the player toolbar: cover + title/album text + the trailing
/// star/«…» controls, wrapped in its own hover-driven surface.
///
/// This is extracted from `MainView` so the player-state reads
/// (`currentSong`, `lastError`) are tracked at *this* view's scope rather than
/// `MainView.body`. Previously those reads happened synchronously inside
/// `MainView`'s `body` evaluation (via `lcdSurface` / `nowPlayingBlock` /
/// `topTrailingControls` getters), which meant every track change — and every
/// read of player state — invalidated the **entire** toolbar (the context menu,
/// all the `.help` text, the generic `Menu`/`Button` metadata) and forced a full
/// `MainView` rebuild. Now only this view (and the `MinimalScrubber`, which was
/// already isolated) reacts to player updates.
struct PlayerLCDView: View {
    @Environment(AppState.self) private var app

    @State private var coverHovered = false
    @State private var hoverText = false
    @State private var hoverTrailing = false
    @State private var hoverScrubber = false
    private var nowHovered: Bool { coverHovered || hoverText || hoverTrailing || hoverScrubber }

    private var isTahoeOrLater: Bool {
        if #available(macOS 26, *) {
            true
        } else {
            false
        }
    }

    var body: some View {
        // body-hover breaks Tahoe principal (see bisect A/B). Keep only
        // contextMenu on the body; hover is tracked interiorly.
        lcdBlock
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .contextMenu {
                if let song = app.player.displaySong {
                    NowPlayingActionMenuItems(song: song)
                }
            }
    }

    private var lcdBlock: some View {
        ZStack {
            lcdContent
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(AMColor.surfaceLight)
                }
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    if app.player.displaySong != nil {
                        MinimalScrubber(
                            isLCDHovered: nowHovered,
                            onHover: { hoverScrubber = $0 }
                        )
                            // Greedy GeometryReader would span the whole LCD and its
                            // tracking would shadow every zone beneath (seen as s1
                            // everywhere). Constrain to the real strip: heights must
                            // mirror MinimalScrubber.hitHeight (18 hovered / 12 idle).
                            // onHover BEFORE padding: padding area must not track
                            // (it leaked onto the cover zone 0–42).
                            .frame(maxWidth: .infinity, alignment: .bottom)
                            .frame(height: nowHovered ? 18 : 12)
                            .onHover { hoverScrubber = $0 }
                            .padding(.leading, 42)
                            .padding(.trailing, 2)
                            .transition(.opacity)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if app.player.displaySong != nil {
                        TopTrailingControlsView(
                            song: app.player.displaySong,
                            nowHovered: nowHovered
                        )
                        .contentShape(Rectangle())
                        .onHover { hoverTrailing = $0 }
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if let error = app.player.lastError {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(AMColor.accent)
                            .lineLimit(1)
                            .padding(.leading, 44)
                            .padding(.bottom, 20)
                            .transition(.opacity)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5)
                        .allowsHitTesting(false)
                }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 42)
    }

    private var lcdContent: some View {
        ZStack(alignment: .leading) {
            textColumn

            coverButton
        }
    }

    /// Hover/tap/menu sit directly on the artwork content: Tahoe principal
    /// installs tracking only for views with real rendered content, while
    /// transparent Color.clear layers never fire there.
    private var coverButton: some View {
        ZStack {
            // Concrete ZStack (NOT Group): hover/tap/menu tracking does not
            // install on Group with conditional branches on Tahoe principal.
            ZStack {
                if let song = app.player.displaySong {
                    CoverArtView(coverArt: song.coverArt, size: 42, cornerRadius: 0, shadow: false)
                        .allowsHitTesting(false)
                } else {
                    ZStack {
                        Rectangle().fill(Color.primary.opacity(0.08))
                        Image(systemName: "music.note")
                            .foregroundStyle(.tertiary)
                    }
                    .allowsHitTesting(false)
                }
            }
            .frame(width: 42, height: 42)
            .overlay {
                if coverHovered, app.player.displaySong != nil {
                    Rectangle().fill(.black.opacity(0.35))
                        .transition(.opacity)
                }
            }
            .overlay {
                if coverHovered, app.player.displaySong != nil {
                    Image(systemName: "pip")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .transition(.opacity)
                }
            }
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 4,
                    bottomLeadingRadius: 4,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 0,
                    style: .continuous
                )
            )
        }
        .frame(width: 42, height: 42)
        .contentShape(Rectangle())
        .onHover { coverHovered = $0 }
        // No song = nothing to show in the mini-player: an empty panel is
        // worse than no panel, so the placeholder cover is not actionable.
        .onTapGesture {
            guard app.player.displaySong != nil else { return }
            MiniPlayerPanelController.shared.show(app: app)
        }
        .contextMenu {
            if let song = app.player.displaySong {
                NowPlayingActionMenuItems(song: song)
            }
        }
        .animation(.snappy(duration: 0.15), value: coverHovered)
        .help(Text(verbatim: "Открыть мини-плеер"))
        .accessibilityLabel(app.player.displaySong == nil
            ? String(localized: "Нет воспроизведения") : "Открыть мини-плеер")
    }

    private var textColumn: some View {
        VStack(alignment: .leading, spacing: 1) {
            FadeTruncatedLabel(
                text: app.player.displaySong?.displayTitle ?? "",
                font: .system(size: 12, weight: .medium),
                color: .primary,
                minLeading: 50,
                minTrailing: nowHovered ? 42 : 24
            )

            FadeTruncatedLabel(
                text: app.player.displaySong?.displaySubtitle ?? "",
                font: .system(size: 12),
                color: .secondary,
                minLeading: nowHovered ? 68 : 50,
                minTrailing: nowHovered ? 38 : 24
            )
        }
        // Full LCD height: content stays vertically centered, left aligned.
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .leading)
        .clipped()
        .contentShape(Rectangle())
        // Directly on the VStack (real Text content): transparent layers do
        // not install tracking on Tahoe principal.
        .onHover { hoverText = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(app.player.displaySong?.displayTitle ?? "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            if let song = app.player.displaySong {
                showGoToMenu(for: song, app: app)
            }
        }
        .onTapGesture {
            if let song = app.player.displaySong {
                showGoToMenu(for: song, app: app)
            }
        }
    }
}

/// Star + ellipsis controls overlaid at the LCD's trailing edge. Their common
/// square hitbox drives the text's reserved trailing area. Reads only the
/// `song` passed in, so it re-evaluates when the track changes, not on every
/// unrelated `MainView` invalidation.
struct TopTrailingControlsView: View {
    static let actionButtonSide: CGFloat = 18

    @Environment(AppState.self) private var app

    let song: SubsonicSong?
    let nowHovered: Bool

    private var isCurrentStarred: Bool {
        song.map { app.isStarred($0) } ?? false
    }

    var body: some View {
        HStack(spacing: 2) {
            if let song {
                NowPlayingEllipsisMenu(song: song)
                    .opacity(nowHovered ? 1 : 0)
                    .allowsHitTesting(nowHovered)
            }

            Button {
                if let song { app.toggleStar(song) }
            } label: {
                Image(systemName: isCurrentStarred ? "star.fill" : "star")
                    .font(.system(size: 12))
                    .foregroundStyle(isCurrentStarred ? AMColor.accent : Color.secondary)
                    .symbolEffect(.bounce, options: .speed(1.8), value: isCurrentStarred)
                    .frame(width: Self.actionButtonSide, height: Self.actionButtonSide)
                    .hoverFill(fill: Color.primary.opacity(0.08), cornerRadius: 2)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .disabled(song == nil)
            .help(Text(verbatim: "В избранное"))
            .accessibilityLabel("В избранное")
            .opacity(song == nil ? 0 : 1)
            .allowsHitTesting(song != nil)
        }
        .frame(height: 28)
        .padding(.trailing, 4)
        .offset(y: -2)
    }
}

/// Apple Music-style context menu for the currently playing song. Built from
/// the same canonical `SongActionItems` used by every song surface, so the
/// playback-bar actions match the rows' right-click and hover menus.
struct NowPlayingEllipsisMenu: View {
    let song: SubsonicSong

    var body: some View {
        Menu {
            NowPlayingActionMenuItems(song: song)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(
            width: TopTrailingControlsView.actionButtonSide - 4,
            height: TopTrailingControlsView.actionButtonSide - 4
        )
        .padding(.trailing, 3)
        .contentShape(Rectangle())
        .help(Text(verbatim: "Ещё"))
        .accessibilityLabel("Действия для песни")
    }
}

/// Canonical action content for a now-playing song, shared by the LCD and the
/// mini-player. Surfaces can provide their own visual button without actions
/// drifting apart.
struct NowPlayingActionMenuItems: View {
    @Environment(AppState.self) private var app

    let song: SubsonicSong

    var body: some View {
        SongActionItems(app: app, song: song, selection: [song])
        Divider()
        Button {
            app.playStation(from: song)
        } label: {
            Label("Создать станцию", systemImage: "dot.radiowaves.left.and.right")
        }
        Button {
            app.openSongDetails(song)
        } label: {
            Label("Сведения", systemImage: "info.circle")
        }
        if let albumID = song.albumId {
            Button {
                app.openAlbumInLibrary(
                    .nowPlayingSummary(from: song, albumID: albumID)
                )
            } label: {
                Label("Показать альбом в медиатеке", systemImage: "square.stack")
            }
        }
        Divider()
        Button {
            copyNowPlaying()
        } label: {
            Label("Скопировать", systemImage: "doc.on.doc")
        }
    }

    private func copyNowPlaying() {
        let parts = [song.displayTitle, song.artist, song.album].compactMap { $0 }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(parts.joined(separator: " — "), forType: .string)
    }
}

/// Standalone downloads icon — an independent toolbar control anchored to its
/// own arrowed popover. Extracted from `MainView` so the frequently-updating
/// `overallDownloadProgress` invalidates only this view, not the whole toolbar.
struct DownloadsToolbarButton: View {
    @Environment(AppState.self) private var app
    @Binding var showDownloads: Bool

    var body: some View {
        Group {
            if app.hasDownloadContent {
                Button {
                    showDownloads.toggle()
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 14))
                            .foregroundStyle(showDownloads ? AMColor.accent : Color.secondary)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.secondary.opacity(0.25))
                                if let progress = app.overallDownloadProgress {
                                    Capsule()
                                        .fill(AMColor.accent)
                                        .frame(width: geo.size.width * progress)
                                }
                            }
                        }
                        .frame(height: 2)
                        .opacity(app.overallDownloadProgress != nil ? 1 : 0)
                    }
                    .frame(width: 24, height: 30)
                    .hoverFill()
                }
                .buttonStyle(.plain)
                .help("Загрузки")
                .accessibilityLabel("Загрузки")
                .popover(isPresented: $showDownloads, arrowEdge: .bottom) {
                    DownloadsPopoverView()
                }
            }
        }
        .animation(.snappy(duration: 0.15), value: app.hasDownloadContent)
    }
}
