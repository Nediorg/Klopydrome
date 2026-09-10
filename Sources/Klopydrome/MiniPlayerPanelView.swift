import NavidromeClient
import SwiftUI

/// The lower extension of the mini-player. It intentionally uses the same
/// lyrics renderer and queue primitives as the main window while leaving the
/// square artwork stage unchanged above it.
struct MiniPlayerPanelView: View {
    @Environment(AppState.self) private var app

    let panel: AppState.PlayerPanelTab

    var body: some View {
        Group {
            switch panel {
            case .lyrics:
                LyricsView()
            case .queue:
                MiniPlayerQueueView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            ZStack {
                VisualEffectView(material: .sidebar, blendingMode: .withinWindow)
                AMColor.background.opacity(0.68)
            }
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AMColor.divider)
                .frame(height: 0.5)
        }
    }
}

private struct MiniPlayerQueueView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        Group {
            if app.player.queue.isEmpty {
                ContentUnavailableView(
                    "Очередь пуста.",
                    systemImage: "text.line.first.and.arrowtriangle.forward"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(app.player.queue.enumerated()), id: \.element.id) { index, song in
                            MiniPlayerQueueRow(
                                song: song,
                                isCurrent: app.player.displaySong?.id == song.id
                            ) {
                                app.player.jump(to: index)
                            }
                        }
                    }
                    .padding(12)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

private struct MiniPlayerQueueRow: View {
    let song: SubsonicSong
    let isCurrent: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                CoverArtView(coverArt: song.coverArt, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.displayTitle)
                        .font(.callout.weight(isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? AMColor.accent : AMColor.primaryText)
                        .lineLimit(1)
                    Text(song.artist ?? "")
                        .font(.caption)
                        .foregroundStyle(AMColor.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let duration = song.duration {
                    Text(Player.format(seconds: Double(duration)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AMColor.secondaryText)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovering ? Color.primary.opacity(0.08) : .clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.14), value: isHovering)
    }
}
