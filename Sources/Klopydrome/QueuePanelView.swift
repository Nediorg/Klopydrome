import SwiftUI
import NavidromeClient

/// Floating slide-out panel at the trailing edge that hosts either the lyrics
/// or the playback queue. Both toolbar buttons (lyrics / up next) drive this
/// one panel, so opening one and collapsing always work together. Overlaid on
/// the whole window (see MainView), so it sizes and surfaces itself: a fixed
/// inspector width on an ultra-thin material that lets the content behind it
/// show through as it slides over.
struct PlayerPanelView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        Group {
            if app.showLyrics {
                LyricsView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(24)
            } else {
                QueuePanelView()
            }
        }
        .frame(width: LayoutMetrics.inspectorIdealWidth)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
}

/// Slide-out "Up Next" queue panel docked at the trailing edge of the main
/// content area. Shows the playback queue (Up Next) or the play history.
/// Animated with a spring and a trailing-edge move transition in MainView.
struct QueuePanelView: View {
    enum Tab: Hashable {
        case upNext
        case history
    }

    @Environment(AppState.self) private var app
    @State private var selectedTab: Tab = .upNext
    @State private var clearHovered = false

    @State private var confirmingClear = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("Вкладка очереди", selection: $selectedTab) {
                Text("Далее".localized).tag(Tab.upNext)
                Text("История".localized).tag(Tab.history)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding()

            HStack {
                Text(selectedTab == .upNext ? "Далее" : "История")
                    .font(.headline)
                Spacer()
                Button {
                    confirmingClear = true
                } label: {
                    Text("Очистить".localized)
                        .font(.callout)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .contentShape(Rectangle())
                        .background {
                            if clearHovered {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.primary.opacity(0.08))
                            }
                        }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(list.isEmpty)
                .onHover { clearHovered = $0 }
                .animation(.snappy(duration: 0.15), value: clearHovered)
                .help("Очистить список")
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            Divider()

            if list.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { index, song in
                            QueueTrackRow(song: song, isCurrent: isCurrent(song)) {
                                select(song, at: index)
                            }
                            Divider().padding(.leading, 56)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity)
        .confirmationDialog(
            selectedTab == .upNext ? "Очистить очередь?" : "Очистить историю?",
            isPresented: $confirmingClear,
            titleVisibility: .visible
        ) {
            Button("Очистить", role: .destructive) { clearAction() }
            Button("Отмена", role: .cancel) {}
        }
    }

    private var list: [SubsonicSong] {
        switch selectedTab {
        case .upNext: return app.player.queue
        case .history:
            var seen = Set<String>()
            return app.player.history.reversed().filter { seen.insert($0.id).inserted }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: selectedTab == .upNext ? "list.bullet" : "clock")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text(selectedTab == .upNext ? "Очередь пуста" : "Истории прослушивания ещё нет")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func isCurrent(_ song: SubsonicSong) -> Bool {
        app.player.currentSong?.id == song.id
    }

    private func select(_ song: SubsonicSong, at index: Int) {
        switch selectedTab {
        case .upNext:
            if let queueIndex = app.player.queue.firstIndex(where: { $0.id == song.id }) {
                app.player.jump(to: queueIndex)
            }
        case .history:
            // История — лог, а не очередь (как в Apple Music)
            app.player.play([song], recordHistory: false)
        }
    }

    private func clearAction() {
        switch selectedTab {
        case .upNext:
            app.player.setQueue([])
        case .history:
            app.player.clearHistory()
        }
    }
}

/// A single queue track row: artwork, title, artist — album and duration,
/// with a macOS hover highlight and red accent for the current track.
struct QueueTrackRow: View {
    let song: SubsonicSong
    let isCurrent: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                CoverArtView(coverArt: song.coverArt, size: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(song.displayTitle)
                        .font(.subheadline)
                        .fontWeight(isCurrent ? .semibold : .regular)
                        .foregroundStyle(isCurrent ? .white : .primary)
                        .lineLimit(1)
                    Text(song.displaySubtitle)
                        .font(.caption)
                        .foregroundStyle(isCurrent ? .white.opacity(0.8) : .secondary)
                        .lineLimit(1)
                }

                Spacer()

                if let duration = song.duration {
                    Text(Player.format(seconds: Double(duration)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(isCurrent ? .white.opacity(0.8) : .secondary)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal)
            .contentShape(Rectangle())
            .background {
                if isCurrent {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(AMColor.accent)
                } else if hovering {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.06))
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
        .accessibilityLabel(song.displayTitle)
    }
}
