import SwiftUI
import NavidromeClient

/// Transport buttons (shuffle / previous / play-pause / next / repeat) shared
/// by the window toolbar and the mini-player, so the actions, labels, and the
/// repeat-icon mapping have a single source of truth. Each surface keeps its
/// own geometry via `Style`: `.toolbar` is the compact toolbar row, `.miniPlayer`
/// the mini-player row with the large circle play button.
struct TransportControls: View {
    enum Style {
        case toolbar
        case miniPlayer
    }

    var style: Style = .toolbar

    @Environment(AppState.self) private var app
    @State private var shuffleHover = false
    @State private var repeatHover = false

    var body: some View {
        switch style {
        case .toolbar: toolbarRow
        case .miniPlayer: miniPlayerRow
        }
    }

    /// Repeat-mode glyph: one-song repeat shows the "1" badge.
    private var repeatIcon: String {
        switch app.player.repeatMode {
        case .one: return "repeat.1"
        default: return "repeat"
        }
    }

    // MARK: Toolbar (compact)

    private var toolbarRow: some View {
        HStack(spacing: 5) {
            Button {
                app.player.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 13))
                    .foregroundStyle(
                        shuffleHover && !app.player.shuffle
                            ? Color.primary.opacity(0.9)
                            : (app.player.shuffle ? AMColor.accent : Color.secondary)
                    )
                    .brightness(shuffleHover && app.player.shuffle ? 0.22 : 0)
                    .frame(minWidth: 30, minHeight: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!app.player.hasQueue)
            .onHover { shuffleHover = $0 }
            .accessibilityLabel("Перемешать")
            .help("Перемешать")

            sideButton("backward.fill",
                        fontSize: 16,
                        color: .secondary,
                        help: "Назад") {
                app.player.previous()
            }
            .frame(width: 30, height: 24)
            .hoverFill()

            Button {
                app.player.togglePlayPause()
            } label: {
                Image(systemName: app.player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 23))
                    .contentTransition(.symbolEffect(.replace, options: .speed(1.8)))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!app.player.hasQueue)
            .hoverFill(fill: Color.primary.opacity(0.12))
            .foregroundStyle(Color.primary)
            .animation(.snappy(duration: 0.14, extraBounce: 0), value: app.player.isPlaying)
            .help("Играть/Пауза")
            .accessibilityLabel(app.player.isPlaying ? "Pause" : "Play")

            sideButton("forward.fill",
                        fontSize: 16,
                        color: .secondary,
                        help: "Вперёд") {
                app.player.next()
            }
            .frame(width: 30, height: 24)
            .hoverFill()

            Button {
                app.player.cycleRepeat()
            } label: {
                Image(systemName: repeatIcon)
                    .font(.system(size: 13))
                    .foregroundStyle(
                        repeatHover && app.player.repeatMode == .off
                            ? Color.primary.opacity(0.9)
                            : (app.player.repeatMode != .off ? AMColor.accent : Color.secondary)
                    )
                    .brightness(repeatHover && app.player.repeatMode != .off ? 0.22 : 0)
                    .frame(minWidth: 30, minHeight: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!app.player.hasQueue)
            .onHover { repeatHover = $0 }
            .accessibilityLabel("Повтор")
            .help("Повтор")
        }
    }

    // MARK: Mini-player

    private var miniPlayerRow: some View {
        HStack(spacing: 28) {
            sideButton("shuffle",
                       fontSize: 16,
                       accent: app.player.shuffle,
                       help: "Перемешать") {
                app.player.toggleShuffle()
            }
            .frame(width: 24, height: 24)
            .hoverFill(cornerRadius: 2)

            sideButton("backward.fill",
                       fontSize: 18,
                       color: nil,
                       help: "Назад") {
                app.player.previous()
            }
            .frame(width: 30, height: 30)
            .hoverFill(cornerRadius: 2)

            Button {
                app.player.togglePlayPause()
            } label: {
                if app.player.isLoading && !app.player.isPlaying {
                    ProgressView().controlSize(.large)
                        .frame(width: 60, height: 60)
                } else {
                    Image(systemName: app.player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 60))
                        .contentTransition(.symbolEffect(.replace, options: .speed(1.8)))
                        .frame(width: 60, height: 60)
                        .hoverFill(fill: Color.primary.opacity(0.08))
                }
            }
            .buttonStyle(.plain)
            .disabled(!app.player.hasQueue)
            .animation(.snappy(duration: 0.14, extraBounce: 0), value: app.player.isPlaying)
            .help("Играть/Пауза")
            .accessibilityLabel(app.player.isPlaying ? "Pause" : "Play")

            sideButton("forward.fill",
                       fontSize: 18,
                       color: nil,
                       help: "Вперёд") {
                app.player.next()
            }
            .frame(width: 30, height: 30)
            .hoverFill(cornerRadius: 2)

            sideButton(repeatIcon,
                       fontSize: 15,
                       accent: app.player.repeatMode != .off,
                       help: "Повтор") {
                app.player.cycleRepeat()
            }
            .frame(width: 24, height: 24)
            .hoverFill(cornerRadius: 2)
        }
    }

    /// One of the four uniform transport buttons. `color` applies only when the
    /// button is not accent-tinted; `nil` keeps the system default (as the mini
    /// player's prev/next do). `disabled` overrides the queue-empty disable for
    /// controls that stay enabled (the toolbar's repeat). The label is framed to
    /// the standard 30×30 hit target INSIDE the button: a frame applied outside
    /// the button only resizes the container, leaving the clickable zone stuck
    /// on the icon glyph.
    @ViewBuilder
    private func sideButton(_ symbol: String,
                             fontSize: CGFloat,
                             accent: Bool = false,
                             color: Color? = .secondary,
                             disabled: Bool? = nil,
                             help: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: fontSize))
                .foregroundStyle(accent ? AMColor.accent : color ?? Color.primary)
                .frame(minWidth: 30, minHeight: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled ?? !app.player.hasQueue)
        .accessibilityLabel(help)
        .help(help)
    }
}
