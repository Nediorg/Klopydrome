import AppKit
import NavidromeClient
import SwiftUI

/// A compact, artwork-first player window. The cover remains a square at every
/// size; controls are temporary overlays so an idle mini-player is only art.
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

    /// The mini-player surfaces the same panel as the main window: the lyrics /
    /// queue selection is AppState's, so the global menu commands and the
    /// mini-player's own pills stay mutually exclusive and in sync.
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
        // The global menu («Очередь»/«Текст») drives AppState directly, so
        // route its changes back into the panel the same way the pills do.
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
            }

            MiniPlayerWindowDragRegion()
                .frame(width: side, height: side)

            if controlsVisible {
                MiniPlayerControlsLayer(
                    song: song,
                    showingVolume: $showingVolume,
                    togglePanel: togglePanel
                )
                .environment(\.colorScheme, .dark)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: controlsVisible)
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
        isHovering = hovering

        guard !hovering else {
            controlsRemainVisible = true
            updateWindowChrome(true, activePanel)
            return
        }

        // The SwiftUI tracking rect ends where the AppKit window chrome
        // begins: stepping onto the traffic lights fires exit although the
        // cursor never left the window. Hiding on that exit strands the
        // lights hidden (no re-enter ever comes from AppKit territory), so
        // the hide applies only once the cursor is truly outside the panel.
        hideControlsTask = Task { @MainActor in
            while MiniPlayerPanelController.shared.isCursorInsidePanel {
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
            }
            showingVolume = false
            controlsRemainVisible = false
            updateWindowChrome(false, activePanel)
        }
    }

    private func togglePanel(_ panel: AppState.PlayerPanelTab) {
        app.togglePlayerPanel(panel)
    }
}

/// The temporary player surface rendered over artwork. It uses AppKit blur, not
/// Tahoe's Liquid Glass, and keeps the artwork visible through a darkened matte.
private struct MiniPlayerControlsLayer: View {
    private static let trackActionSide: CGFloat = 21

    @Environment(AppState.self) private var app

    let song: SubsonicSong
    @Binding var showingVolume: Bool
    let togglePanel: (AppState.PlayerPanelTab) -> Void

    @State private var isHoveringStar = false
    @State private var isHoveringEllipsis = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                VStack(spacing: 0) {
                    header
                    Spacer(minLength: 0)
                    bottomControlShield
                        .frame(height: proxy.size.height * 0.68)
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
        }
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
                        .foregroundStyle(.white.opacity(0.64))
                        .lineLimit(1)
                }
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

            VStack(spacing: 6) {
                PlaybackSlider(
                    trackOpacity: 0.18,
                    progressColor: .white,
                    progressOpacity: 0.62
                )
                MiniPlayerTimeRow()
            }
            .padding(.top, 18)

            MiniPlayerTransportControls()
                .padding(.top, 9)
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
            .help(app.isStarred(song) ? "Убрать из избранного".localized : "В избранное".localized)
            .accessibilityLabel(app.isStarred(song) ? "Убрать из избранного".localized : "В избранное".localized)

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
            .help("Ещё".localized)
            .accessibilityLabel("Действия для песни".localized)
        }
    }

    private var bottomControlShield: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
            LinearGradient(
                colors: [.black.opacity(0.02), .black.opacity(0.22)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.8), location: 0.34),
                    .init(color: .black, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
    }
}

/// A native hit-test region that drags the panel from the artwork while
/// SwiftUI controls above it retain their own mouse interaction.
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
