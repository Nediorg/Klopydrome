import AppKit
import NavidromeClient
import SwiftUI

// MARK: - Detail Player Header Bar (Apple Music style)

/// The player header bar that lives at the top of the detail column: transport
/// controls, adaptive LCD, volume, and lyrics/queue buttons.
struct PlayerHeaderBar: View {
    @Environment(AppState.self) private var app
    @Binding var path: NavigationPath
    @Binding var showDownloads: Bool
    var isMiniPlayerVisible: Bool

    var body: some View {
        GeometryReader { geo in
            let windowX = geo.frame(in: .global).minX
            // When the sidebar is collapsed (minX < 120), leave room for the window traffic lights and sidebar toggle.
            let trafficLightOffset = windowX < 120 ? max(0, 104 - windowX) : 0

            HStack(spacing: 0) {
                // Leading edge / traffic light offset
                Spacer(minLength: 8)
                    .frame(width: max(16, trafficLightOffset))

                // Leading group: [back] [media]
                if !isMiniPlayerVisible {
                    HStack(spacing: 8) {
                        let showBack = !path.isEmpty || app.nav.selectedPlaylist != nil
                        backButton
                            .opacity(showBack ? 1 : 0)
                            .allowsHitTesting(showBack)
                            .accessibilityHidden(!showBack)
                        TransportControls(style: .toolbar)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(2)
                }

                // Flexible spacer between transport and center LCD
                Spacer(minLength: 8)

                // Center group: [downloads?] [lcd] [crossfade?]
                if !isMiniPlayerVisible {
                    HStack(spacing: 8) {
                        if app.hasDownloadContent {
                            DownloadsToolbarButton(showDownloads: $showDownloads)
                        }
                        PlayerLCDView(path: $path)
                            .frame(
                                minWidth: LayoutMetrics.playerBarMinWidth,
                                maxWidth: LayoutMetrics.playerBarMaxWidth
                            )
                        CrossfadeToolbarIndicator()
                    }
                    .layoutPriority(1)
                }

                // Flexible spacer between center LCD and right controls
                Spacer(minLength: 8)

                // Trailing group: [volume / lyrics / queue]
                if !isMiniPlayerVisible {
                    rightControls
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(2)
                }

                // Trailing edge spacer
                Spacer(minLength: 8)
                    .frame(width: 12)
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
    }

    /// Inline "back" chevron at the player bar's leading edge (Apple Music
    /// style). Pops a pushed sub-page (album/artist/playlist opened from within
    /// a tab) or, when a sidebar playlist is open, returns to "All Playlists".
    private var backButton: some View {
        Button {
            if !path.isEmpty {
                path.removeLast()
            } else if app.nav.selectedPlaylist != nil {
                app.nav.selected = .playlists
                app.nav.selectedPlaylist = nil
            }
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
