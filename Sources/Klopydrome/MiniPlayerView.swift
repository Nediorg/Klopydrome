import AppKit
import NavidromeClient
import SwiftUI

struct MiniPlayerView: View {
    @Environment(AppState.self) private var app

    @State private var isHovering = false
    @State private var controlsRemainVisible = false
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var showingVolume = false

    private let updateWindowChrome: (Bool, AppState.PlayerPanelTab?) -> Void
    @AppStorage("debugShowPlayerState") private var debugShowPlayerState = false

    init(updateWindowChrome: @escaping (Bool, AppState.PlayerPanelTab?) -> Void) {
        self.updateWindowChrome = updateWindowChrome
    }

    private var activePanel: AppState.PlayerPanelTab? {
        app.visiblePlayerPanel
    }

    private var controlsVisible: Bool {
        isHovering || controlsRemainVisible
    }

    var body: some View {
        GeometryReader { proxy in
            let artworkSide = artworkSide(in: proxy.size)

            if let song = app.player.displaySong {
                artworkStage(song: song, side: artworkSide)
                    .frame(width: artworkSide, height: artworkSide)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                miniPlayerPlaceholder(side: artworkSide)
                    .overlay {
                        MiniPlayerWindowDragRegion()
                    }
                    .frame(width: artworkSide, height: artworkSide)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .topLeading) {
            if debugShowPlayerState {
                VStack(alignment: .leading, spacing: 6) {
                    if !MiniPlayerResizeGeometry.lastDebugLine.isEmpty {
                        TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                            Text(MiniPlayerResizeGeometry.lastDebugLine)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.yellow)
                                .padding(4)
                                .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 4))
                                .allowsHitTesting(false)
                        }
                    }
                    MiniPlayerDebugOverlay(app: app)
                }
                .padding(.top, 36)
                .padding(.leading, 4)
            }
        }
        .onAppear {
            updateWindowChrome(controlsVisible, activePanel)
        }
        .onHover(perform: updateHover)
        .onChange(of: app.visiblePlayerPanel) { _, _ in
            updateWindowChrome(controlsVisible, activePanel)
        }
        .onDisappear {
            hideControlsTask?.cancel()
        }
    }

    private func artworkSide(in size: CGSize) -> CGFloat {
        max(0, size.width)
    }

    private func artworkStage(song: SubsonicSong, side: CGFloat) -> some View {
        ZStack {
            miniPlayerPlaceholder(side: side)

            if let coverArt = song.coverArt, !coverArt.isEmpty {
                CoverArtView(
                    coverArt: coverArt,
                    size: side,
                    cornerRadius: 0,
                    shadow: false,
                    placeholderBackground: .clear
                )
                .transition(.opacity)
            }

            MiniPlayerWindowDragRegion()
                .frame(width: side, height: side)

            MiniPlayerControlsLayer(
                song: song,
                side: side,
                showingVolume: $showingVolume,
                togglePanel: togglePanel
            )
            .environment(\.colorScheme, .dark)
            .opacity(controlsVisible ? 1 : 0)
            .animation(.easeOut(duration: 0.2), value: controlsVisible)
            .allowsHitTesting(controlsVisible)
        }
    }

    private func miniPlayerPlaceholder(side: CGFloat) -> some View {
        ZStack {
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)

            Image(systemName: "music.note")
                .font(.system(size: side * 0.38, weight: .light))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .frame(width: side, height: side)
    }

    private func updateHover(_ hovering: Bool) {
        hideControlsTask?.cancel()

        guard !hovering else {
            isHovering = true
            controlsRemainVisible = true
            updateWindowChrome(true, activePanel)
            return
        }

        isHovering = false

        hideControlsTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }

            while MiniPlayerPanelController.shared.isCursorInsidePanel
                || MiniPlayerPanelController.shared.isLiveResizing
                || NSEvent.pressedMouseButtons != 0 {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
            }
            showingVolume = false
            controlsRemainVisible = false
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            if !controlsVisible {
                updateWindowChrome(false, activePanel)
            }
        }
    }

    private func togglePanel(_ panel: AppState.PlayerPanelTab) {
        app.togglePlayerPanel(panel)
    }
}

private struct MiniPlayerControlsLayer: View {
    private static let trackActionSide: CGFloat = 21

    @Environment(AppState.self) private var app

    let song: SubsonicSong
    let side: CGFloat
    @Binding var showingVolume: Bool
    let togglePanel: (AppState.PlayerPanelTab) -> Void

    @State private var isHoveringStar = false
    @State private var isHoveringEllipsis = false

    var body: some View {
        ZStack {
            MiniPlayerBlurredArtworkView(coverArt: song.coverArt, size: side)

            VStack(spacing: 0) {
                header
                Spacer(minLength: 0)
            }

            trackDetails
                .padding(.horizontal, 28)
                .padding(.bottom, 14)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .bottomLeading
                )
        }
        .frame(width: side, height: side)
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack {
            Spacer(minLength: 84)
            MiniPlayerTopControls(
                showingVolume: $showingVolume,
                togglePanel: togglePanel
            )
        }
        .padding(.top, MiniPlayerLayout.topMenuEdgeInset)
        .padding(.trailing, MiniPlayerLayout.topMenuTrailingInset)
    }

    private var trackDetails: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.displayTitle)
                        .font(.title3.weight(.bold))
                        .lineLimit(1)
                    Text(song.displaySubtitle)
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.70))
                        .lineLimit(1)
                }
                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                .contentShape(Rectangle())
                .onTapGesture { showGoToMenu(for: song, app: app) }

                Spacer(minLength: 8)
                trackActions
            }
            .padding(.top, 3)

            if let error = app.player.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(2)
                    .padding(.top, 8)
            }

            VStack(spacing: 4) {
                PlaybackSlider(
                    trackOpacity: 0.18,
                    progressColor: .white,
                    progressOpacity: 0.62
                )
                MiniPlayerTimeRow()
            }
            .padding(.top, 12)

            MiniPlayerTransportControls()
                .padding(.top, 6)
        }
    }

    private var trackActions: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.snappy(duration: 0.15)) {
                    app.toggleStar(song)
                }
            } label: {
                Image(systemName: app.isStarred(song) ? "star.fill" : "star")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isHoveringStar ? Color.black.opacity(0.85) : Color.white)
                    .frame(width: Self.trackActionSide, height: Self.trackActionSide)
                    .miniPlayerMatteCircle(fill: isHoveringStar ? .white.opacity(0.75) : .white.opacity(0.30))
                    .contentShape(Circle())
            }
            .buttonStyle(MiniPlayerActionButtonStyle())
            .onHover { isHoveringStar = $0 }
            .help(app.isStarred(song) ? "Remove from Favorites".localized : "Add to Favorites".localized)
            .accessibilityLabel(app.isStarred(song) ? "Remove from Favorites".localized : "Add to Favorites".localized)

            ZStack {
                Image(systemName: "ellipsis")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(isHoveringEllipsis ? Color.black.opacity(0.85) : Color.white)
                    .frame(width: Self.trackActionSide, height: Self.trackActionSide)
                    .miniPlayerMatteCircle(fill: isHoveringEllipsis ? .white.opacity(0.75) : .white.opacity(0.30))

                Menu {
                    NowPlayingActionMenuItems(song: song)
                } label: {
                    Image(nsImage: EllipsisMenuIcon.transparentImage(size: Self.trackActionSide))
                        .frame(width: Self.trackActionSide, height: Self.trackActionSide)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: Self.trackActionSide, height: Self.trackActionSide)
            }
            .frame(width: Self.trackActionSide, height: Self.trackActionSide)
            .contentShape(Circle())
            .onHover { isHoveringEllipsis = $0 }
            .help("More".localized)
            .accessibilityLabel("Song Actions".localized)
        }
    }
}

private struct MiniPlayerWindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        MiniPlayerWindowDragView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class MiniPlayerWindowDragView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

extension View {
    func miniPlayerMatteCircle(fill: Color = .white.opacity(0.30)) -> some View {
        background(fill, in: Circle())
            .overlay {
                Circle().strokeBorder(.white.opacity(0.28), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.28), radius: 6, y: 2)
    }
}

private struct MiniPlayerActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
