import SwiftUI
import AppKit

struct AppCommandMenus: Commands {
    let app: AppState

    @CommandsBuilder
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(L10n.text("О приложении Klopydrome")) { showAboutPanel() }
        }
        playbackMenu
        controlsMenu
        viewMenu
        CommandGroup(replacing: .windowArrangement) {}
        CommandGroup(replacing: .windowList) {}
    }

    /// Every toolbar transport control must also exist as a menu command.
    @CommandsBuilder
    private var playbackMenu: some Commands {
        CommandMenu("Воспроизведение") {
            Button(app.player.isPlaying ? "Пауза" : "Слушать") {
                app.player.togglePlayPause()
            }
            .disabled(!app.player.hasQueue)

            Button("Остановить") {
                app.player.stop()
            }
            .disabled(!app.player.hasQueue)

            Divider()

            Button("Следующий трек") {
                app.player.next()
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .disabled(!app.player.hasQueue)

            Button("Предыдущий трек") {
                app.player.previous()
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .disabled(!app.player.hasQueue)

            Divider()

            Button("Увеличить громкость") {
                app.player.adjustVolume(by: 0.05)
            }
            .keyboardShortcut(.upArrow, modifiers: .command)

            Button("Уменьшить громкость") {
                app.player.adjustVolume(by: -0.05)
            }
            .keyboardShortcut(.downArrow, modifiers: .command)
        }
    }

    @CommandsBuilder
    private var controlsMenu: some Commands {
        CommandMenu("Управление") {
            Menu("Повтор") {
                repeatMenuItem("Выключить", mode: .off)
                repeatMenuItem("Все", mode: .all)
                repeatMenuItem("Одну песню", mode: .one)
            }

            Divider()

            Menu("Перемешивание") {
                Button {
                    app.player.setShuffleEnabled(true)
                } label: {
                    shuffleMenuLabel("Включить", selected: app.player.shuffle)
                }
                .disabled(!app.player.hasQueue || app.player.shuffle)

                Button {
                    app.player.setShuffleEnabled(false)
                } label: {
                    shuffleMenuLabel("Выключить", selected: !app.player.shuffle)
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
                Button("Возобновить активность...".localized) {
                    app.resumeDiscordSnooze()
                }
                .disabled(!app.serverConfig.effectiveDiscordRichPresenceEnabled)
            } else {
                Menu("Приостановить активность...".localized) {
                    Button("Навсегда".localized) {
                        app.snoozeDiscord(for: nil)
                    }
                    Divider()
                    Button("На 15 минут".localized) {
                        app.snoozeDiscord(for: 15 * 60)
                    }
                    Button("На 1 час".localized) {
                        app.snoozeDiscord(for: 60 * 60)
                    }
                    Button("На 8 часов".localized) {
                        app.snoozeDiscord(for: 8 * 60 * 60)
                    }
                    Button("На 24 часа".localized) {
                        app.snoozeDiscord(for: 24 * 60 * 60)
                    }
                }
                .disabled(!app.serverConfig.effectiveDiscordRichPresenceEnabled)
            }
        }
    }

    @CommandsBuilder
    private var viewMenu: some Commands {
        CommandGroup(after: .toolbar) {
            // Radio-style, not independent checkboxes: the two player panels are
            // mutually exclusive (a single `visiblePlayerPanel`), so only one
            // checkmark can ever be shown and toggling one replaces the other.
            panelMenuItem("Очередь", tab: .queue, shortcut: "u")
            panelMenuItem("Текст", tab: .lyrics, shortcut: "l")
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
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
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
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
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
}
