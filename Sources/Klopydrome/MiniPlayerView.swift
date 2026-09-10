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
    @State private var navigationPath = NavigationPath()
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
        Group {
            if let song = app.player.displaySong {
                playerContent(for: song)
            } else {
                Color.clear
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

    private func playerContent(for song: SubsonicSong) -> some View {
        GeometryReader { proxy in
            let artworkSide = artworkSide(in: proxy.size)

            artworkStage(song: song, side: artworkSide)
                .frame(width: artworkSide, height: artworkSide)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func artworkSide(in size: CGSize) -> CGFloat {
        max(0, size.width)
    }

    private func artworkStage(song: SubsonicSong, side: CGFloat) -> some View {
        ZStack {
            CoverArtView(
                coverArt: song.coverArt,
                size: side,
                cornerRadius: 0,
                shadow: false,
                placeholderBackground: AMColor.background
            )

            MiniPlayerWindowDragRegion()
                .frame(width: side, height: side)

            if controlsVisible {
                MiniPlayerControlsLayer(
                    song: song,
                    navigationPath: $navigationPath,
                    showingVolume: $showingVolume,
                    togglePanel: togglePanel
                )
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: controlsVisible)
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
    @Binding var navigationPath: NavigationPath
    @Binding var showingVolume: Bool
    let togglePanel: (AppState.PlayerPanelTab) -> Void

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
                HStack {
                    Text(app.player.formattedCurrentTime())
                    Spacer()
                    Text(app.player.formattedRemainingTime())
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.62))
            }
            .padding(.top, 18)

            MiniPlayerTransportControls()
                .padding(.top, 9)
        }
    }

    private var trackActions: some View {
        HStack(spacing: 10) {
            Button {
                app.toggleStar(song)
            } label: {
                Image(systemName: app.isStarred(song) ? "star.fill" : "star")
                    .font(.system(size: 10, weight: .semibold))
                    .symbolEffect(.bounce, options: .speed(1.8), value: app.isStarred(song))
                    .frame(width: Self.trackActionSide, height: Self.trackActionSide)
                    .miniPlayerMatteCircle(fill: .white.opacity(0.30))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("В избранное")
            .accessibilityLabel("В избранное")

            Menu {
                NowPlayingActionMenuItems(song: song, path: $navigationPath, inMiniPlayer: true)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: Self.trackActionSide, height: Self.trackActionSide)
                    .miniPlayerMatteCircle(fill: .white.opacity(0.30))
                    .contentShape(Circle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("Ещё")
            .accessibilityLabel("Действия для песни")
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

private struct MiniPlayerTopControls: View {
    private enum Control: Hashable {
        case lyrics
        case queue
        case volume
    }

    @Environment(AppState.self) private var app
    @State private var hoveredControl: Control?
    @State private var secondaryControlsVisible = true
    @State private var volumeBarExpanded = false
    @State private var volumeSliderVisible = false
    @State private var volumeTransitionTask: Task<Void, Never>?

    @Binding var showingVolume: Bool
    let togglePanel: (AppState.PlayerPanelTab) -> Void

    var body: some View {
        HStack(spacing: 8) {
            if volumeBarExpanded {
                MatteVolumeSlider(value: Bindable(app).player.volume)
                    .frame(width: 144)
                    .opacity(volumeSliderVisible ? 1 : 0)
                    .allowsHitTesting(volumeSliderVisible)
            } else {
                secondaryControls
                    .opacity(secondaryControlsVisible ? 1 : 0)
                    .allowsHitTesting(secondaryControlsVisible)
            }

            volumeButton
        }
        .padding(.leading, volumeBarExpanded ? 12 : 3)
        .padding(.trailing, 3)
        .padding(.vertical, 3)
        .matteTopControlSurface()
        .animation(.easeOut(duration: 0.16), value: volumeBarExpanded)
        .animation(.easeOut(duration: 0.08), value: volumeSliderVisible)
    }

    private var secondaryControls: some View {
        HStack(spacing: 4) {
            panelButton(.lyrics, systemName: "quote.bubble", control: .lyrics)
            panelButton(.queue, systemName: "list.bullet", control: .queue)
            Rectangle()
                .fill(.white.opacity(0.32))
                .frame(width: 1, height: 22)
                .padding(.horizontal, 3)
        }
    }

    private var volumeButton: some View {
        Button {
            showingVolume ? dismissVolumeSlider() : presentVolumeSlider()
        } label: {
            Image(systemName: volumeIcon)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 38, height: 38)
                .background(hoveredControl == .volume ? .white.opacity(0.28) : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredControl = $0 ? .volume : nil }
        .help(showingVolume ? "Скрыть громкость" : "Громкость")
        .accessibilityLabel(showingVolume ? "Скрыть громкость" : "Громкость")
    }

    private func presentVolumeSlider() {
        volumeTransitionTask?.cancel()
        showingVolume = true
        withAnimation(.linear(duration: 0.1)) {
            secondaryControlsVisible = false
        }
        volumeTransitionTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.16)) {
                volumeBarExpanded = true
            }
            do {
                try await Task.sleep(for: .milliseconds(160))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.08)) {
                volumeSliderVisible = true
            }
        }
    }

    private func dismissVolumeSlider() {
        volumeTransitionTask?.cancel()
        withAnimation(.linear(duration: 0.1)) {
            volumeSliderVisible = false
        }
        volumeTransitionTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.16)) {
                volumeBarExpanded = false
            }
            do {
                try await Task.sleep(for: .milliseconds(160))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            withAnimation(.linear(duration: 0.1)) {
                secondaryControlsVisible = true
            }
            showingVolume = false
        }
    }

    private func panelButton(
        _ panel: AppState.PlayerPanelTab,
        systemName: String,
        control: Control
    ) -> some View {
        Button {
            togglePanel(panel)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 38, height: 38)
                .background(buttonFill(for: panel, control: control), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredControl = $0 ? control : nil }
        .help(panel.title)
        .accessibilityLabel(panel.title)
    }

    private func buttonFill(for panel: AppState.PlayerPanelTab, control: Control) -> Color {
        if app.visiblePlayerPanel == panel { return AMColor.accent.opacity(0.82) }
        return hoveredControl == control ? .white.opacity(0.28) : .clear
    }

    private var volumeIcon: String {
        if app.player.volume == 0 { return "speaker.slash.fill" }
        if app.player.volume < 0.5 { return "speaker.wave.1.fill" }
        return "speaker.wave.2.fill"
    }
}

private extension View {
    func matteTopControlSurface() -> some View {
        background {
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                .clipShape(Capsule())
        }
        .overlay {
            Capsule().strokeBorder(.white.opacity(0.32), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.28), radius: 8, y: 3)
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
    func miniPlayerMatteCircle(fill: Color = .white.opacity(0.24)) -> some View {
        background(fill, in: Circle())
            .overlay {
                Circle().strokeBorder(.white.opacity(0.28), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.18), radius: 7, y: 2)
    }
}
