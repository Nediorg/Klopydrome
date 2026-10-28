import AppKit
import NavidromeClient
import SwiftUI

struct PlayerHeaderBar: View {
    @Environment(AppState.self) private var app
    @Binding var showDownloads: Bool
    var isMiniPlayerVisible: Bool

    var body: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let windowX = geo.frame(in: .global).minX
            let trafficLightOffset = windowX < 120 ? max(0, 134 - windowX) : 0
            let leadingInset = max(16, trafficLightOffset)
            let trailingInset: CGFloat = 12

            let leadingWidth: CGFloat = 208
            let trailingWidth: CGFloat = 216

            let leadingWing = leadingInset + leadingWidth
            let trailingWing = trailingInset + trailingWidth

            let satelliteAllowance: CGFloat = 24 + 8

            let effectiveLeadingWing = leadingWing + satelliteAllowance
            let effectiveTrailingWing = trailingWing + satelliteAllowance
            let maxEffectiveWing = max(effectiveLeadingWing, effectiveTrailingWing)
            let safeMargin: CGFloat = 8

            let maxSafeCenteredSpace = max(0, (totalWidth / 2 - maxEffectiveWing - safeMargin) * 2)

            let desiredLCDWidth = totalWidth * LayoutMetrics.playerBarMaxFraction
            let targetLCDWidth = min(
                LayoutMetrics.playerBarMaxWidth,
                max(LayoutMetrics.playerBarMinWidth, desiredLCDWidth)
            )
            let finalLCDWidth = min(targetLCDWidth, maxSafeCenteredSpace)
            let showCenterGroup = !isMiniPlayerVisible && maxSafeCenteredSpace >= 150

            ZStack {
                HeaderBarWindowDragRegion()

                if showCenterGroup {
                    centerGroup(width: finalLCDWidth)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .transaction { $0.animation = nil }
                }

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
        ZStack {
            PlayerLCDView()
                .frame(width: width)
                .transaction { $0.animation = nil }

            if app.hasDownloadContent {
                HStack {
                    DownloadsToolbarButton(showDownloads: $showDownloads)
                    Spacer()
                }
                .frame(width: width + 2 * (24 + 8))
                .transition(.opacity)
            }

            if app.player.lastError != nil {
                HStack {
                    Spacer()
                    PlayerErrorToolbarIndicator()
                }
                .frame(width: width + 2 * (24 + 8))
                .transition(.opacity)
            } else if app.player.isCrossfading {
                HStack {
                    Spacer()
                    CrossfadeToolbarIndicator()
                }
                .frame(width: width + 2 * (24 + 8))
                .transition(.opacity)
            }
        }
        .transaction { $0.animation = nil }
        .animation(.snappy(duration: 0.2), value: app.hasDownloadContent)
        .animation(.snappy(duration: 0.2), value: app.player.isCrossfading)
        .animation(.snappy(duration: 0.2), value: app.player.lastError != nil)
    }

    private var rightControls: some View {
        HStack(spacing: 8) {
            ToolbarVolumeControl(player: app.player)

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
                .help("Lyrics".localized)
                .accessibilityLabel("Lyrics".localized)

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
                .help("Queue".localized)
                .accessibilityLabel("Queue".localized)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

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
        .help("Back".localized)
        .accessibilityLabel("Back".localized)
    }
}

private struct ToolbarVolumeControl: View {
    @Bindable var player: Player

    var body: some View {
        HStack(spacing: 4) {
            VolumeEdgeButton(
                systemImage: "speaker.fill",
                label: L10n.text("action.volume.mute"),
                symbolOffset: 7
            ) {
                player.volume = 0
            }
            ToolbarVolumeSlider(value: $player.volume)
                .frame(width: 75, height: 52)
                .help("Volume".localized)
            VolumeEdgeButton(
                systemImage: "speaker.wave.3.fill",
                label: L10n.text("action.volume.maximum")
            ) {
                player.volume = 1
            }
        }
    }
}
