import AppKit
import SwiftUI
import NavidromeClient

struct SongRow: View {
    let song: SubsonicSong
    var index: Int?
    var showAlbum: Bool = true
    var showsArtist: Bool = false
    /// When non-nil, overrides the environment-derived current-track check.
    /// Lets parents pass a snapshot and enables `Equatable` skipping when
    /// `AppState` ticks for unrelated reasons (progress, downloads).
    var isCurrentOverride: Bool?
    /// Surface-specific prefix items for the row's context menu (e.g. «Убрать
    /// из плейлиста»); the canonical `SongActionItems` always follow.
    var extraMenuItems: (() -> AnyView)?
    var onPlay: ((Int) -> Void)?
    /// Whether this row is part of the current selection. Nil = selection not
    /// supported on this surface (e.g. compact rows).
    var isSelected: Bool = false
    /// Full selection for bulk context-menu actions when multiple rows are selected.
    var selectedSongs: [SubsonicSong] = []
    /// Called when the user clicks the row (without double-click intent).
    var onSelect: (() -> Void)?

    @Environment(AppState.self) private var app
    @State private var hovering = false

    private var isCurrent: Bool { isCurrentOverride ?? (app.player.currentSong?.id == song.id) }
    private var fgPrimary: Color { isCurrent ? .white : .primary }
    private var fgSecondary: Color { isCurrent ? .white.opacity(0.8) : .secondary }
    private var isDownloading: Bool { app.downloadingSongIDs.contains(song.id) }
    private var isCachedLocally: Bool { app.isCached(song) }
    private var isStarred: Bool { app.isStarred(song) }
    private var isCurrentPlaying: Bool { isCurrent && app.player.isPlaying }
    private var starForeground: Color { AMColor.accent }

    /// Songs that context-menu bulk actions apply to.
    private var actionTargets: [SubsonicSong] {
        isSelected && selectedSongs.count > 1 ? selectedSongs : [song]
    }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                app.toggleStar(song)
            } label: {
                Image(systemName: isStarred ? "star.fill" : "star")
                    .font(.system(size: 11))
                    .foregroundStyle(starForeground)
            }
            .buttonStyle(.plain)
            .help(isStarred ? "Убрать из избранного".localized : "В избранное".localized)
            .opacity(isStarred ? 1 : (hovering ? 1 : 0))
            .allowsHitTesting(hovering || isStarred)
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())

            SongRowEdgeLayout(spacing: 10, minHeight: showAlbum ? 36 : (showsArtist ? 30 : 20)) {
                leadingContent
                trailingContent
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background {
                if isCurrent {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(AMColor.accent)
                } else if isSelected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(AMColor.sidebarSelection.opacity(0.55))
                } else if hovering {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.06))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { onPlay?(index ?? 0) }
            .simultaneousGesture(TapGesture().onEnded { onSelect?() })
            .contextMenu {
                if let extraMenuItems { extraMenuItems() }
                SongActionItems(
                    app: app,
                    song: song,
                    selection: actionTargets,
                    onPlay: onPlay.map { play in { play(index ?? 0) } }
                )
            }
        }
        .frame(minHeight: showAlbum ? 46 : (showsArtist ? 40 : 32))
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.15), value: hovering)
        .animation(.snappy(duration: 0.12), value: isSelected)
    }

    @ViewBuilder
    private var leadingContent: some View {
        HStack(spacing: 10) {
            if !showAlbum {
                ZStack {
                    if isCurrent {
                        if hovering {
                            Image(systemName: isCurrentPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(fgPrimary)
                        } else {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(fgPrimary)
                        }
                    } else if hovering {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(fgPrimary)
                    } else if let index {
                        Text("\(index + 1)")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(fgSecondary)
                    }
                }
                .frame(width: 22, alignment: .trailing)
                .contentShape(Rectangle())
                .onTapGesture {
                    if isCurrent {
                        app.player.togglePlayPause()
                    } else {
                        onPlay?(index ?? 0)
                    }
                }
            }
            if showAlbum {
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
                        Image(systemName: isCurrentPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
                .onTapGesture {
                    if isCurrent {
                        app.player.togglePlayPause()
                    } else {
                        onPlay?(index ?? 0)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(song.displayTitle)
                    .font(.callout)
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .foregroundStyle(fgPrimary)
                    .lineLimit(1)
                if showAlbum {
                    Text(song.displaySubtitle)
                        .font(.caption)
                        .foregroundStyle(fgSecondary)
                        .lineLimit(1)
                } else if showsArtist, let artist = song.artist {
                    Text(artist)
                        .font(.caption)
                        .foregroundStyle(fgSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
        }
    }

    @ViewBuilder
    private var trailingContent: some View {
        HStack(spacing: 10) {
            if isDownloading {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 16, height: 16)
                    .help("Загрузка…".localized)
                    .accessibilityLabel("Загрузка".localized)
            } else {
                Button {
                    if isCachedLocally {
                        Task { await app.removeFromCache(song) }
                    } else {
                        app.cacheSong(song)
                    }
                } label: {
                    Image(systemName: isCachedLocally ? "checkmark.circle.fill" : "arrow.down.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(isCachedLocally ? AMColor.accent : Color.secondary)
                        .symbolEffect(.bounce, value: isCachedLocally)
                }
                .buttonStyle(.plain)
                .help(isCachedLocally ? "Удалить загрузку".localized : "Загрузить".localized)
                .accessibilityLabel(isCachedLocally ? "Удалить загрузку".localized
                                                    : (isDownloading ? "Загрузка".localized : "Загрузить".localized))
                .opacity(hovering || isCachedLocally ? 1 : 0)
                .allowsHitTesting(hovering || isCachedLocally)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
                .transition(.opacity)
                .accessibilityHidden(false)
            }
            if let duration = song.duration {
                Text(Player.format(seconds: Double(duration)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(fgSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            SongEllipsisMenu(song: song,
                             foregroundStyle: isCurrent ? .white : .secondary,
                             app: app,
                             extraMenuItems: extraMenuItems)
                .opacity(hovering ? 1 : 0)
                .allowsHitTesting(hovering)
                .animation(.snappy(duration: 0.12), value: hovering)
                .accessibilityHidden(false)
        }
    }
}

private struct SongRowEdgeLayout: Layout {
    let spacing: CGFloat
    var minHeight: CGFloat = 34

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout CGFloat
    ) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        // Cache trailing width — it depends only on the trailing content
        // (duration + stars + buttons), not on the proposed width, so it is
        // stable across the two layout passes (sizeThatFits + placeSubviews).
        if cache == 0 {
            cache = subviews[1].sizeThatFits(.unspecified).width
        }
        let leading = subviews[0].sizeThatFits(.unspecified)
        let idealWidth = leading.width + spacing + cache
        let contentHeight = max(leading.height, subviews[1].sizeThatFits(.unspecified).height)
        let height = max(minHeight, contentHeight)
        return CGSize(width: max(proposal.width ?? idealWidth, idealWidth), height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout CGFloat
    ) {
        guard subviews.count == 2 else { return }
        if cache == 0 {
            cache = subviews[1].sizeThatFits(.unspecified).width
        }
        let leadingWidth = max(0, bounds.width - cache - spacing)
        let height = bounds.height

        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: bounds.midY),
            anchor: .leading,
            proposal: ProposedViewSize(width: leadingWidth, height: height)
        )
        subviews[1].place(
            at: CGPoint(x: bounds.maxX, y: bounds.midY),
            anchor: .trailing,
            proposal: ProposedViewSize(width: cache, height: height)
        )
    }

    func makeCache(subviews: Subviews) -> CGFloat { 0 }
    func updateCache(_ cache: inout CGFloat, subviews: Subviews) {
        // Invalidate when trailing content changes (e.g. rating, duration).
        cache = 0
    }
}

/// Selection state manager for `SongRow`-based lists (album, playlist, smart playlist).
/// Handles Cmd+click (additive toggle) and plain click (replace with single item).
/// Pass `songs` for the full ordered list to support Shift+click range selection.
struct SongRowSelection {
    var ids: Set<SubsonicSong.ID> = []

    /// Toggle or replace selection based on current NSEvent modifier flags.
    mutating func toggle(_ id: SubsonicSong.ID, allSongs: [SubsonicSong]) {
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        if flags.contains(.command) {
            // Cmd+click: additive toggle
            if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        } else if flags.contains(.shift), let anchor = ids.first,
                  let anchorIdx = allSongs.firstIndex(where: { $0.id == anchor }),
                  let targetIdx = allSongs.firstIndex(where: { $0.id == id }) {
            // Shift+click: range from first selected item to target
            let range = min(anchorIdx, targetIdx)...max(anchorIdx, targetIdx)
            ids = Set(allSongs[range].map(\.id))
        } else {
            // Plain click: if already the only selection, deselect; else select only this
            ids = ids == [id] ? [] : [id]
        }
    }

    func isSelected(_ id: SubsonicSong.ID) -> Bool { ids.contains(id) }

    func selectedSongs(from allSongs: [SubsonicSong]) -> [SubsonicSong] {
        allSongs.filter { ids.contains($0.id) }
    }
}
