import AppKit
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
        ZStack {
            if app.showLyrics {
                LyricsView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(24)
                    .transition(.identity)
            } else {
                QueuePanelView()
                    .transition(.identity)
            }
        }
        .animation(nil, value: app.showLyrics)
        .frame(width: LayoutMetrics.inspectorIdealWidth)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(AMColor.divider)
                .frame(width: 0.5)
        }
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

    @State private var confirmingClear = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("Вкладка очереди".localized, selection: $selectedTab) {
                Text("Далее".localized).tag(Tab.upNext)
                Text("История".localized).tag(Tab.history)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding()

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Text((selectedTab == .upNext ? "На очереди" : "История").localized)
                        .font(.system(size: 15, weight: .bold))
                    if selectedTab == .upNext, let subtitle = app.player.queueContextSubtitle {
                        Text(subtitle)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(AMColor.secondaryText)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if !list.isEmpty {
                    Button {
                        confirmingClear = true
                    } label: {
                        Text("Очистить".localized)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(AMColor.accent)
                    }
                    .buttonStyle(.plain)
                    .help("Очистить список".localized)
                }
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
                            QueueTrackRow(
                                song: song,
                                isCurrent: isCurrent(song),
                                canRemove: selectedTab == .upNext,
                                onRemove: { app.player.remove(at: index) },
                                showDivider: index < list.count - 1,
                                action: { select(song, at: index) }
                            )
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.automatic)
                .background(OverlayScrollerModifier())
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity)
        .confirmationDialog(
            selectedTab == .upNext ? "Очистить очередь?".localized : "Очистить историю?".localized,
            isPresented: $confirmingClear,
            titleVisibility: .visible
        ) {
            Button("Очистить".localized, role: .destructive) { clearAction() }
            Button("Отмена".localized, role: .cancel) {}
        }
    }

    private var list: [SubsonicSong] {
        switch selectedTab {
        case .upNext: return app.player.queue
        case .history:
            return app.player.history.reversed().uniqued()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: selectedTab == .upNext ? "list.bullet" : "clock")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text(selectedTab == .upNext ? "Очередь пуста".localized : "Истории прослушивания ещё нет".localized)
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
            app.play([song], at: 0)
        }
    }

    private func clearAction() {
        switch selectedTab {
        case .upNext:
            app.player.stop()
            app.player.setQueue([])
        case .history:
            app.player.clearHistory()
        }
    }
}

/// A single queue track row: artwork with playing/hover overlay, title, artist — album,
/// with a subtle macOS hover highlight, deletion button, ellipsis context menu,
/// and accent color on title for currently playing track.
struct QueueTrackRow: View {
    let song: SubsonicSong
    let isCurrent: Bool
    var canRemove: Bool = false
    var onRemove: (() -> Void)?
    var showDivider: Bool = false
    let action: () -> Void

    @Environment(AppState.self) private var app
    @State private var hovering = false
    @State private var hoverTracker = HoverTracker()

    private var isPlaying: Bool { isCurrent && app.player.isPlaying }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    CoverArtView(coverArt: song.coverArt, size: 36, cornerRadius: 4)

                    if isCurrent && !hovering {
                        Color.black.opacity(0.35)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.white)
                    } else if hovering {
                        Color.black.opacity(0.35)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 0) {
                    Text(song.displayTitle)
                        .font(.callout.weight(.regular))
                        .foregroundStyle(isCurrent ? AMColor.accent : AMColor.primaryText)
                        .lineLimit(1)
                    Text(song.displaySubtitle)
                        .font(.callout)
                        .foregroundStyle(AMColor.secondaryText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 4) {
                    if canRemove && hovering {
                        Button {
                            onRemove?()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.secondary)
                                .frame(width: 22, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Удалить из очереди".localized)
                        .transition(.identity)
                    }

                    SongEllipsisMenu(
                        song: song,
                        selection: [song],
                        foregroundStyle: .secondary,
                        app: app,
                        extraActions: canRemove ? [
                            SongMenuExtraAction(
                                title: "Удалить из очереди".localized,
                                systemImage: "trash",
                                action: { onRemove?() }
                            )
                        ] : [],
                        compact: true,
                        side: 24
                    )
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.leading, 7)
            .padding(.trailing, 10)
            .padding(.vertical, 6)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .background {
                if hovering {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                }
            }
        }
        .buttonStyle(.plain)
        .frame(height: 48)
        .overlay(alignment: .bottom) {
            if showDivider {
                Rectangle()
                    .fill(Color.primary.opacity(0.1))
                    .frame(height: 1)
                    .padding(.leading, 55)
                    .padding(.trailing, 10)
            }
        }
        .contextMenu {
            if canRemove {
                Button(role: .destructive) {
                    onRemove?()
                } label: {
                    Label("Удалить из очереди".localized, systemImage: "trash")
                }
                Divider()
            }
            SongActionItems(app: app, song: song, selection: [song])
        }
        .onHover { isInside in
            hoverTracker.isInside = isInside
            if isInside {
                if !ScrollGate.shared.isScrolling && !hovering {
                    hovering = true
                }
            } else {
                if hovering {
                    hovering = false
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ScrollGate.scrollDidStart)) { _ in
            if hovering {
                hovering = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ScrollGate.scrollDidEnd)) { _ in
            if hoverTracker.isInside && !hovering {
                hovering = true
            }
        }
        .onDisappear {
            hoverTracker.isInside = false
            hovering = false
        }
        .accessibilityLabel(song.displayTitle)
    }
}

private struct OverlayScrollerModifier: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        OverlayScrollerView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class OverlayScrollerView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func layout() {
            super.layout()
            enclosingScrollView?.scrollerStyle = .overlay
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            enclosingScrollView?.scrollerStyle = .overlay
        }
    }
}
