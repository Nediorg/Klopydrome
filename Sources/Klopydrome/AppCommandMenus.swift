import SwiftUI
import AppKit

struct AppCommandMenus: Commands {
    let app: AppState
    @AppStorage("debugShowPlayerState") private var isDeveloperMode = false

    @CommandsBuilder
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Klopydrome".localized) { showAboutPanel() }
        }
        CommandGroup(replacing: .newItem) {
            Button("Scan Media Library".localized) {
                Task { await app.triggerServerScan() }
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
            .disabled(!app.isConnected || app.isOfflineSession || app.isServerScanning)

            if isDeveloperMode {
                Divider()
                developerMenuSection
            }
        }
        playbackMenu
        controlsMenu
        viewMenu
        CommandGroup(replacing: .windowArrangement) {}
        CommandGroup(replacing: .windowList) {}
    }

    @CommandsBuilder
    private var playbackMenu: some Commands {
        CommandMenu("Playback".localized) {
            Button((app.player.isPlaying ? "Pause" : "Play").localized) {
                app.player.togglePlayPause()
            }
            .disabled(!app.player.hasQueue)

            Button("Stop".localized) {
                app.player.stop()
            }
            .disabled(!app.player.hasQueue)

            Divider()

            Button("Next Track".localized) {
                app.player.next()
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .disabled(!app.player.hasQueue)

            Button("Previous track".localized) {
                app.player.previous()
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .disabled(!app.player.hasQueue)

            Divider()

            Button("Increase Volume".localized) {
                app.player.adjustVolume(by: 0.05)
            }
            .keyboardShortcut(.upArrow, modifiers: .command)

            Button("Decrease Volume".localized) {
                app.player.adjustVolume(by: -0.05)
            }
            .keyboardShortcut(.downArrow, modifiers: .command)
        }
    }

    @CommandsBuilder
    private var controlsMenu: some Commands {
        CommandMenu("Controls".localized) {
            Menu("Repeat".localized) {
                repeatMenuItem("Off", mode: .off)
                repeatMenuItem("All", mode: .all)
                repeatMenuItem("One Song", mode: .one)
            }

            Divider()

            Menu("Shuffling".localized) {
                Button {
                    app.player.setShuffleEnabled(true)
                } label: {
                    shuffleMenuLabel("On", selected: app.player.shuffle)
                }
                .disabled(!app.player.hasQueue || app.player.shuffle)

                Button {
                    app.player.setShuffleEnabled(false)
                } label: {
                    shuffleMenuLabel("Off", selected: !app.player.shuffle)
                }
                .disabled(!app.player.hasQueue || !app.player.shuffle)

                Divider()

                ForEach(ShuffleMode.allCases) { mode in
                    Button {
                        app.player.setShuffleMode(mode)
                    } label: {
                        shuffleMenuLabel(
                            mode.label,
                            selected: app.player.shuffleMode == mode
                        )
                    }
                    .disabled(!app.player.hasQueue)
                }
            }

            Divider()

            if app.isDiscordSnoozed {
                Button("Show Activity".localized) {
                    app.resumeDiscordSnooze()
                }
                .disabled(!app.serverConfig.effectiveDiscordRichPresenceEnabled)
            } else {
                Menu("Hide Activity".localized) {
                    Button("For This Track".localized) {
                        app.snoozeDiscordForCurrentTrack()
                    }
                    .disabled(app.player.currentSong == nil)
                    Divider()
                    Button("For 15 Minutes".localized) {
                        app.snoozeDiscord(for: 15 * 60)
                    }
                    Button("For 1 Hour".localized) {
                        app.snoozeDiscord(for: 60 * 60)
                    }
                    Button("For 8 Hours".localized) {
                        app.snoozeDiscord(for: 8 * 60 * 60)
                    }
                    Button("For 24 Hours".localized) {
                        app.snoozeDiscord(for: 24 * 60 * 60)
                    }
                    Divider()
                    Button("Forever".localized) {
                        app.snoozeDiscord(for: nil)
                    }
                }
                .disabled(!app.serverConfig.effectiveDiscordRichPresenceEnabled)
            }
        }
    }

    @CommandsBuilder
    private var viewMenu: some Commands {
        CommandGroup(after: .toolbar) {
            panelMenuItem("Queue", tab: .queue, shortcut: "u")
            panelMenuItem("Lyrics", tab: .lyrics, shortcut: "l")
        }
    }

    @ViewBuilder
    private func panelMenuItem(
        _ title: String,
        tab: AppState.PlayerPanelTab,
        shortcut: KeyEquivalent
    ) -> some View {
        Button {
            app.togglePlayerPanel(tab)
        } label: {
            if app.visiblePlayerPanel == tab {
                Label(title.localized, systemImage: "checkmark")
            } else {
                Text(title.localized)
            }
        }
        .keyboardShortcut(shortcut, modifiers: [.command, .option])
    }

    @ViewBuilder
    private func repeatMenuItem(_ title: String, mode: Player.RepeatMode) -> some View {
        Button {
            app.player.setRepeatMode(mode)
        } label: {
            if app.player.repeatMode == mode {
                Label(title.localized, systemImage: "checkmark")
            } else {
                Text(title.localized)
            }
        }
    }

    @ViewBuilder
    private func shuffleMenuLabel(_ title: String, selected: Bool) -> some View {
        if selected {
            Label(title.localized, systemImage: "checkmark")
        } else {
            Text(title.localized)
        }
    }

    private func showAboutPanel() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        let credits = NSMutableAttributedString()
        let titleStyle = NSMutableParagraphStyle()
        titleStyle.paragraphSpacing = 2
        let linkStyle = NSMutableParagraphStyle()
        linkStyle.paragraphSpacing = 10
        for entry in LicenseData.entries {
            let line = NSMutableAttributedString(string: "\(entry.title) — \(entry.subtitle)\n")
            line.addAttributes(
                [
                    .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                    .paragraphStyle: titleStyle
                ],
                range: NSRange(location: 0, length: line.length)
            )
            credits.append(line)
            let link = NSMutableAttributedString(string: "\(entry.linkTitle)\n")
            let linkURL = entry.url ?? URL(string: entry.urlString) ?? URL(string: "https://example.com")!
            link.addAttributes(
                [
                    .link: linkURL,
                    .font: NSFont.systemFont(ofSize: 10),
                    .paragraphStyle: linkStyle
                ],
                range: NSRange(location: 0, length: link.length)
            )
            credits.append(link)
        }
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: "Klopydrome",
            .applicationVersion: version,
            .version: build,
            .credits: credits
        ])
    }

    @ViewBuilder
    private var developerMenuSection: some View {
        Menu("Developer Tools") {
            Button("Simulate Error on Current Playlist") {
                let current = app.nav.history.last ?? app.nav.selectedPlaylist.map { .playlist($0) }
                if case .playlist(let summary) = current {
                    app.simulatePlaylistLoadError(for: summary.id, message: "The request timed out (Simulated).")
                }
            }

            Button("Force Reload Current View") {
                let current = app.nav.history.last ?? app.nav.selectedPlaylist.map { .playlist($0) }
                if case .playlist(let summary) = current {
                    app.loadPlaylistIfNeeded(summary, forceReload: true)
                }
            }

            Divider()

            Button("Clear All Playlist Load States") {
                app.cancelPlaylistLoads()
            }

            Button("Clear Image & Metadata In-Memory Cache") {
                CoverArtStore.shared.clearMemoryCache()
            }

            Divider()

            Button("Drop Active Server Connection") {
                app.disconnect()
            }
        }
    }
}
