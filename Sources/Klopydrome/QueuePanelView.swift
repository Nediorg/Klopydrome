import AppKit
import SwiftUI
import NavidromeClient

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
            Picker("Queue Tab".localized, selection: $selectedTab) {
                Text("Playing Next".localized).tag(Tab.upNext)
                Text("History".localized).tag(Tab.history)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding()

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Text((selectedTab == .upNext ? "Up Next" : "History").localized)
                        .font(.headline.weight(.semibold))
                    if selectedTab == .upNext, let subtitle = app.player.queueContextSubtitle {
                        Text(subtitle)
                            .font(.callout)
                            .foregroundStyle(AMColor.secondaryText)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if !list.isEmpty {
                    Button {
                        confirmingClear = true
                    } label: {
                        Text("Clear".localized)
                            .font(.callout)
                            .foregroundStyle(AMColor.accent)
                    }
                    .buttonStyle(.plain)
                    .help("Clear".localized)
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
                        ForEach(0..<list.count, id: \.self) { index in
                            let song = list[index]
                            QueueTrackRow(
                                song: song,
                                isCurrent: selectedTab == .upNext ? (index == app.player.currentIndex) : isCurrent(song),
                                canRemove: selectedTab == .upNext,
                                onRemove: { app.removeFromQueue(at: index) },
                                showDivider: index < list.count - 1,
                                action: { select(song, at: index) }
                            )
                            .modifier(QueueRowDragDropModifier(
                                isEnabled: selectedTab == .upNext,
                                index: index,
                                song: song,
                                exportInfo: { app.exportInfo(for: song) },
                                onDrop: { payload in
                                    handleDrop(payload, targetIndex: index)
                                }
                            ))
                        }
                        if selectedTab == .upNext {
                            Color.clear
                                .frame(height: 28)
                                .contentShape(Rectangle())
                                .modifier(PlaylistRowReorderModifier(
                                    isEnabled: true,
                                    onDrop: { payload in
                                        handleDrop(payload, targetIndex: app.player.queue.count)
                                    }
                                ))
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.automatic)
                .dropDestination(for: TrackDragPayload.self) { items, _ in
                    guard selectedTab == .upNext, let payload = items.first else { return false }
                    handleDrop(payload, targetIndex: app.player.queue.count)
                    return true
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity)
        .confirmationDialog(
            selectedTab == .upNext ? "Clear Queue?".localized : "Clear History?".localized,
            isPresented: $confirmingClear,
            titleVisibility: .visible
        ) {
            Button("Clear".localized, role: .destructive) { clearAction() }
            Button("Cancel".localized, role: .cancel) {}
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
            Text(selectedTab == .upNext ? "Queue is empty".localized : "No listening history yet".localized)
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
            if app.player.queue.indices.contains(index) {
                app.player.jump(to: index)
            }
        case .history:
            app.play(song)
        }
    }

    private func clearAction() {
        switch selectedTab {
        case .upNext:
            app.clearQueue()
        case .history:
            app.clearHistory()
        }
    }

    static func queueMoveDestination(from srcIndex: Int, to targetIndex: Int, count: Int) -> Int? {
        guard srcIndex >= 0, srcIndex < count else { return nil }
        let clamped = min(max(targetIndex, 0), count)
        guard srcIndex != clamped, srcIndex + 1 != clamped else { return nil }
        return clamped
    }

    private func handleDrop(_ payload: TrackDragPayload, targetIndex: Int) {
        switch payload.kind {
        case .queueItem(let srcIndex, _):
            guard let destination = Self.queueMoveDestination(
                from: srcIndex,
                to: targetIndex,
                count: app.player.queue.count
            ) else { return }
            app.moveInQueue(fromOffsets: IndexSet(integer: srcIndex), toOffset: destination)
        default:
            Task {
                let songs = await app.resolveSongs(for: payload)
                guard !songs.isEmpty else { return }
                app.insertIntoQueue(songs, at: targetIndex)
                app.saveQueueToServer()
            }
        }
    }
}

private struct QueueRowDragDropModifier: ViewModifier {
    let isEnabled: Bool
    let index: Int
    let song: SubsonicSong
    let exportInfo: () -> TrackDragPayload.ExportInfo
    let onDrop: (TrackDragPayload) -> Void

    @State private var isTargeted = false

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .trackDraggable(
                    label: { song.displayTitle },
                    payload: {
                        TrackDragPayload.queueItem(index: index, songID: song.id, exportInfo: exportInfo())
                    }
                )
                .dropDestination(for: TrackDragPayload.self) { items, _ in
                    guard let payload = items.first else { return false }
                    onDrop(payload)
                    return true
                } isTargeted: { targeted in
                    isTargeted = targeted
                }
                .overlay(alignment: .top) {
                    if isTargeted {
                        Rectangle()
                            .fill(AMColor.accent)
                            .frame(height: 2)
                            .padding(.horizontal, 4)
                    }
                }
        } else {
            content
        }
    }
}

struct QueueTrackRow: View {
    let song: SubsonicSong
    let isCurrent: Bool
    var canRemove: Bool = false
    var onRemove: (() -> Void)?
    var showDivider: Bool = false
    let action: () -> Void

    @Environment(AppState.self) private var app
    @State private var hovering = false

    private var isPlaying: Bool { isCurrent && app.player.isPlaying }

    var body: some View {
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
                HStack(spacing: 4) {
                    Text(song.displayTitle)
                        .font(AMFont.rowTitle)
                        .foregroundStyle(isCurrent ? AMColor.accent : AMColor.primaryText)
                        .lineLimit(1)
                    if song.isExplicit {
                        ExplicitBadge()
                    }
                }
                Text(song.displaySubtitle)
                    .font(AMFont.rowSubtitle)
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
                    .help("Remove from Queue".localized)
                    .transition(.identity)
                }

                SongEllipsisMenu(
                    song: song,
                    selection: [song],
                    foregroundStyle: .secondary,
                    app: app,
                    extraActions: canRemove ? [
                        SongMenuExtraAction(
                            title: "Remove from Queue".localized,
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
        .onTapGesture(perform: action)
        .accessibilityAddTraits(.isButton)
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
                    Label("Remove from Queue".localized, systemImage: "trash")
                }
                Divider()
            }
            SongActionItems(app: app, song: song, selection: [song])
        }
        .onHover { hovering = $0 }
        .accessibilityLabel(song.displayTitle)
    }
}
