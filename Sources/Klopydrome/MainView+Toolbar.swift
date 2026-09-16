import AppKit
import NavidromeClient
import SwiftUI

// MARK: - Detail Player Header Bar (Apple Music style)

/// The player header bar that lives at the top of the detail column: transport
/// controls, adaptive LCD, volume, and lyrics/queue buttons.
struct PlayerHeaderBar: View {
    @Environment(AppState.self) private var app
    @Binding var showDownloads: Bool
    var isMiniPlayerVisible: Bool

    var body: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let windowX = geo.frame(in: .global).minX
            // When the sidebar is collapsed (minX < 120), leave room for the window traffic lights and sidebar toggle.
            let trafficLightOffset = windowX < 120 ? max(0, 104 - windowX) : 0
            let leadingInset = max(16, trafficLightOffset)
            let trailingInset: CGFloat = 12

            let leadingWidth: CGFloat = 208
            let trailingWidth: CGFloat = 199
            let maxWing = max(leadingInset + leadingWidth, trailingInset + trailingWidth)

            let downloadsWidth: CGFloat = app.hasDownloadContent ? 36 : 0
            let crossfadeWidth: CGFloat = app.player.crossfadeStatusText != nil ? 34 : 0
            let extraCenterWidth = downloadsWidth + crossfadeWidth

            // Space available for centered LCD without overlapping leading/trailing wings
            let maxCenteredSpace = max(0, (totalWidth / 2 - maxWing - 12) * 2 - extraCenterWidth)

            let desiredLCDWidth = totalWidth * LayoutMetrics.playerBarMaxFraction
            let targetLCDWidth = min(
                LayoutMetrics.playerBarMaxWidth,
                max(LayoutMetrics.playerBarMinWidth, desiredLCDWidth)
            )
            let finalLCDWidth: CGFloat = max(240, min(targetLCDWidth, maxCenteredSpace))

            ZStack {
                HeaderBarWindowDragRegion()

                // Center layer: strictly centered in the detail column
                if !isMiniPlayerVisible {
                    centerGroup(width: finalLCDWidth)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                // Edges layer: Leading controls docked left, Trailing controls docked right
                HStack(spacing: 0) {
                    Spacer(minLength: 0).frame(width: leadingInset)

                    if !isMiniPlayerVisible {
                        leadingControls
                    }

                    Spacer(minLength: 12)

                    if !isMiniPlayerVisible {
                        rightControls
                    }

                    Spacer(minLength: 0).frame(width: trailingInset)
                }
            }
            .frame(height: 52)
        }
        .frame(height: 52)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AMColor.divider)
                .frame(height: 0.5)
        }
    }

    private var leadingControls: some View {
        HStack(spacing: 8) {
            let showBack = !app.nav.history.isEmpty || app.nav.selectedPlaylist != nil
            backButton
                .opacity(showBack ? 1 : 0)
                .allowsHitTesting(showBack)
                .accessibilityHidden(!showBack)
            TransportControls(style: .toolbar)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func centerGroup(width: CGFloat) -> some View {
        HStack(spacing: 8) {
            if app.hasDownloadContent {
                DownloadsToolbarButton(showDownloads: $showDownloads)
            }
            PlayerLCDView()
                .frame(width: width)
            CrossfadeToolbarIndicator()
        }
    }

    private var rightControls: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                VolumeEdgeButton(
                    systemImage: "speaker.fill",
                    label: L10n.text("action.volume.mute"),
                    symbolOffset: 7
                ) {
                    app.player.volume = 0
                }
                ToolbarVolumeSlider(value: Bindable(app).player.volume)
                    .frame(width: 75, height: 52)
                    .help("Громкость")
                VolumeEdgeButton(
                    systemImage: "speaker.wave.3.fill",
                    label: L10n.text("action.volume.maximum")
                ) {
                    app.player.volume = 1
                }
            }
            .background(NonDraggableBackground())

            HStack(spacing: 4) {
                Button {
                    app.togglePlayerPanel(.lyrics)
                } label: {
                    Image(systemName: "quote.bubble")
                        .font(.system(size: 16))
                        .foregroundStyle(app.queuePanelVisible && app.showLyrics ? Color.accentColor : Color.secondary)
                        .frame(width: 32, height: 32)
                        .hoverFill()
                }
                .buttonStyle(.plain)
                .help("Текст")
                .accessibilityLabel("Текст")

                Button {
                    app.togglePlayerPanel(.queue)
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 16))
                        .foregroundStyle(app.queuePanelVisible && !app.showLyrics ? Color.accentColor : Color.secondary)
                        .frame(width: 32, height: 32)
                        .hoverFill()
                }
                .buttonStyle(.plain)
                .help("Дальше")
                .accessibilityLabel("Дальше")
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    /// Inline "back" chevron at the player bar's leading edge (Apple Music
    /// style). Pops a pushed sub-page (album/artist/playlist opened from within
    /// a tab) or, when a sidebar playlist is open, returns to "All Playlists".
    private var backButton: some View {
        Button {
            app.navigateBack()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.primary)
                .frame(width: 20, height: 28)
                .contentShape(Rectangle())
                .hoverFill()
        }
        .buttonStyle(.plain)
        .padding(.trailing, 2)
        .help("Назад")
        .accessibilityLabel("Назад")
    }
}
