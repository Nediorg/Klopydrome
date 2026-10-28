import SwiftUI
import NavidromeClient
import AppKit

struct PlayerLCDView: View {
    @Environment(AppState.self) private var app

    @State private var coverHovered = false
    @State private var hoverText = false
    @State private var hoverTrailing = false
    @State private var hoverScrubber = false
    private var nowHovered: Bool { coverHovered || hoverText || hoverTrailing || hoverScrubber }

    var body: some View {
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
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(AMColor.surfaceLight)
                }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    if app.player.displaySong != nil {
                        MinimalScrubber(
                            isLCDHovered: nowHovered,
                            onHover: { hoverScrubber = $0 }
                        )
                            .frame(maxWidth: .infinity, alignment: .bottom)
                            .frame(height: nowHovered ? 18 : 12)
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

                .overlay {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
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
                .frame(width: 42, height: 42, alignment: .leading)
        }
    }

    private var coverButton: some View {
        ZStack {
            ZStack {
                if let song = app.player.displaySong {
                    CoverArtView(coverArt: song.coverArt, size: 42, cornerRadius: 0, shadow: false)
                        .frame(width: 42, height: 42)
                        .clipped()
                        .allowsHitTesting(false)
                } else {
                    ZStack {
                        Rectangle().fill(Color.primary.opacity(0.08))
                        Image(systemName: "music.note")
                            .foregroundStyle(.tertiary)
                    }
                    .frame(width: 42, height: 42)
                    .clipped()
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
        .onHover { hovered in
            coverHovered = hovered
            if hovered, let coverArt = app.player.displaySong?.coverArt {
                MiniPlayerVariableBlurCache.shared.prewarmBlur(
                    coverArt: coverArt,
                    size: MiniPlayerPanelController.shared.userCompactSide
                )
            }
        }
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
        .help("Open MiniPlayer".localized)
        .accessibilityLabel(app.player.displaySong == nil
            ? "Not Playing".localized : "Open MiniPlayer".localized)
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
                minLeading: 50,
                minTrailing: nowHovered ? 38 : 24
            )
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .leading)
        .clipped()
        .contentShape(Rectangle())
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
                if nowHovered {
                    NowPlayingEllipsisMenu(song: song)
                        .transition(.opacity)
                } else {
                    Color.clear
                        .frame(
                            width: Self.actionButtonSide - 4,
                            height: Self.actionButtonSide - 4
                        )
                        .padding(.trailing, 3)
                }
            }

            Button {
                if let song { app.toggleStar(song) }
            } label: {
                Image(systemName: isCurrentStarred ? "star.fill" : "star")
                    .font(.system(size: 12))
                    .foregroundStyle(isCurrentStarred ? AMColor.accent : Color.secondary)
                    .frame(width: Self.actionButtonSide, height: Self.actionButtonSide)
                    .hoverFill(fill: Color.primary.opacity(0.08), cornerRadius: 2)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .disabled(song == nil)
            .help(isCurrentStarred ? "Remove from Favorites".localized : "Add to Favorites".localized)
            .accessibilityLabel(isCurrentStarred ? "Remove from Favorites".localized : "Add to Favorites".localized)
            .opacity(song == nil ? 0 : 1)
            .allowsHitTesting(song != nil)
        }
        .frame(height: 28)
        .padding(.trailing, 4)
        .offset(y: -2)
    }
}

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
        .help("More".localized)
        .accessibilityLabel("Song Actions".localized)
    }
}

struct NowPlayingActionMenuItems: View {
    @Environment(AppState.self) private var app

    let song: SubsonicSong

    var body: some View {
        SongActionItems(app: app, song: song, selection: [song])
    }
}

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
                                    Rectangle()
                                        .fill(AMColor.accent)
                                        .frame(width: geo.size.width * progress)
                                }
                            }
                            .clipShape(Capsule())
                        }
                        .frame(height: 2)
                        .opacity(app.overallDownloadProgress != nil ? 1 : 0)
                    }
                    .frame(width: 24, height: 30)
                    .hoverFill()
                }
                .buttonStyle(.plain)
                .help("Downloads".localized)
                .accessibilityLabel("Downloads".localized)
                .popover(isPresented: $showDownloads, arrowEdge: .bottom) {
                    DownloadsPopoverView()
                }
            }
        }
        .animation(.snappy(duration: 0.15), value: app.hasDownloadContent)
    }
}
