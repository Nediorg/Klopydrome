import SwiftUI

/// Compact transport layout: Shuffle and Repeat remain on the sides, while the
/// previous, play and next actions stay grouped around the visual center.
struct MiniPlayerTransportControls: View {
    private enum EdgeControl {
        case shuffle
        case repeatMode
    }

    @Environment(AppState.self) private var app
    @State private var hoveredEdgeControl: EdgeControl?

    var body: some View {
        HStack {
            edgeButton(
                "shuffle",
                control: .shuffle,
                active: app.player.shuffle,
                help: "Перемешать"
            ) {
                app.player.toggleShuffle()
            }

            Spacer(minLength: 12)

            HStack(spacing: 12) {
                navigationButton("backward.fill", help: "Назад") {
                    app.player.previous()
                }

                playButton

                navigationButton("forward.fill", help: "Вперёд") {
                    app.player.next()
                }
            }

            Spacer(minLength: 12)

            edgeButton(
                repeatIcon,
                control: .repeatMode,
                active: app.player.repeatMode != .off,
                help: "Повтор",
                disabled: false
            ) {
                app.player.cycleRepeat()
            }
        }
    }

    private var playButton: some View {
        Button {
            app.player.togglePlayPause()
        } label: {
            Image(systemName: app.player.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 29, weight: .bold))
                .frame(width: 52, height: 52)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!app.player.hasQueue)
        .help("Играть/Пауза")
        .accessibilityLabel(app.player.isPlaying ? "Пауза" : "Играть")
        .contentTransition(.symbolEffect(.replace, options: .speed(1.8)))
        .animation(.snappy(duration: 0.14, extraBounce: 0), value: app.player.isPlaying)
    }

    private func navigationButton(
        _ symbol: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 23, weight: .semibold))
                .frame(width: 42, height: 42)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!app.player.hasQueue)
        .help(help)
        .accessibilityLabel(help)
    }

    private func edgeButton(
        _ symbol: String,
        control: EdgeControl,
        active: Bool,
        help: String,
        disabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.68))
                .frame(width: 32, height: 32)
                .background(active || hoveredEdgeControl == control ? .white.opacity(0.28) : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredEdgeControl = $0 ? control : nil }
        .disabled(disabled && !app.player.hasQueue)
        .help(help)
        .accessibilityLabel(help)
    }

    private var repeatIcon: String {
        app.player.repeatMode == .one ? "repeat.1" : "repeat"
    }
}
