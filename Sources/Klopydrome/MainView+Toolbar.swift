import SwiftUI

// Moved from MainView.swift to keep that file under the size gate.

extension MainView {
    // MARK: Native window toolbar — Apple Music style transport + LCD + volume
    //
    // Three groups: leading (back+transport), center LCD (principal), trailing
    // (volume+panels). The LCD is fixed 360×42 in the principal slot.

    @ToolbarContentBuilder
    var playerToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            let showBack = !path.isEmpty || app.nav.selectedPlaylist != nil
            HStack(spacing: 8) {
                backButton
                    .opacity(showBack ? 1 : 0)
                    .allowsHitTesting(showBack)
                    .accessibilityHidden(!showBack)
                if !isMiniPlayerVisible {
                    TransportControls(style: .toolbar)
                }
            }
            .padding(.trailing, 4)
            .frame(minWidth: isMiniPlayerVisible ? 0 : LayoutMetrics.toolbarLeadingMinWidth)
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
        }
                ToolbarItem(placement: .principal) {
            if !isMiniPlayerVisible {
                PlayerLCDView(path: $path)
                    .frame(width: 360, height: 42)
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if !isMiniPlayerVisible {
                rightControls
                    .frame(minWidth: LayoutMetrics.toolbarTrailingMinWidth)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
            }
        }
    }
}

// MARK: - Player toolbar content

/// The player toolbar's three placement groups (transport left, LCD center,
/// volume/actions right) plus the individual controls. These live in the real
/// window toolbar, declared on `MainView` so they share its toolbar-group
/// builder and lifted navigation path.
extension MainView {
    /// The LCD + downloads icon that sit in the toolbar's principal + leading
    /// groups. Both are extracted child views (see `PlayerLCDView.swift`) so the
    /// player-state reads inside them are tracked at their own scope rather than
    /// at `MainView.body` — otherwise every track change would rebuild the whole
    /// toolbar.
    func nowPlayingGroup(path: Binding<NavigationPath>) -> some View {
        HStack(spacing: 8) {
            DownloadsToolbarButton(showDownloads: $showDownloads)
            PlayerLCDView(path: path)
            CrossfadeToolbarIndicator()
        }
    }

    private var rightControls: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                VolumeEdgeButton(
                    systemImage: "speaker.fill",
                    label: L10n.text("action.volume.mute")
                ) {
                    app.player.volume = 0
                }
                Slider(value: Bindable(app).player.volume, in: 0...1)
                    .frame(width: 75)
                    .controlSize(.mini)
                    // Match the NowPlaying scrubber's progress fill color.
                    .tint(.secondary)
                    .accessibilityLabel("Громкость")
                    .help("Громкость")
                VolumeEdgeButton(
                    systemImage: "speaker.wave.3.fill",
                    label: L10n.text("action.volume.maximum")
                ) {
                    app.player.volume = 1
                }
            }

            HStack(spacing: 5) {
                Button {
                    app.togglePlayerPanel(.lyrics)
                } label: {
                    Image(systemName: "quote.bubble")
                        .font(.system(size: 18))
                        .foregroundStyle(app.queuePanelVisible && app.showLyrics ? Color.accentColor : Color.secondary)
                        // Label = the hit box: frame + hoverFill inside the
                        // label so the whole rectangle is clickable.
                        .frame(width: 36, height: 36)
                        .hoverFill()
                }
                .buttonStyle(.plain)
                .help("Текст")
                .accessibilityLabel("Текст")

                Button {
                    app.togglePlayerPanel(.queue)
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 18))
                        .foregroundStyle(app.queuePanelVisible && !app.showLyrics ? Color.accentColor : Color.secondary)
                        .frame(width: 36, height: 36)
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
