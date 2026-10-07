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
    /// Whether this row is part of the current selection.
    var isSelected: Bool = false
    /// Lazily resolves the full selection when the context menu opens.
    /// Avoids O(N×M) per render by deferring the work until actually needed.
    var resolveSelection: (() -> [SubsonicSong])?
    /// Called when the user clicks the row (without double-click intent).
    var onSelect: (() -> Void)?

    @Environment(AppState.self) private var app
    @State private var hovering = false
    @State private var hoverTracker = HoverTracker()

    private var isCurrent: Bool { isCurrentOverride ?? (app.player.currentSong?.id == song.id) }
    private var fgPrimary: Color { isCurrent ? .white : .primary }
    private var fgSecondary: Color { isCurrent ? .white.opacity(0.8) : .secondary }
    private var isDownloading: Bool { app.downloadingSongIDs.contains(song.id) }
    private var isCachedLocally: Bool { app.isCached(song) }
    private var isStarred: Bool { app.isStarred(song) }
    private var isCurrentPlaying: Bool { isCurrent && app.player.isPlaying }
    private var starForeground: Color { AMColor.accent }
    private var isPlayableLocally: Bool { !app.isOfflineSession || isCachedLocally }
    private var isNarrow: Bool { !showAlbum && !showsArtist }
    private var rowCornerRadius: CGFloat { isNarrow ? 4 : 6 }

    /// Songs that context-menu bulk actions apply to.
    private var actionTargets: [SubsonicSong] {
        guard isSelected, let resolve = resolveSelection else { return [song] }
        let resolved = resolve()
        return resolved.count > 1 ? resolved : [song]
    }

    var body: some View {
        HStack(spacing: 6) {
            if isStarred || hovering {
                Button {
                    app.toggleStar(song)
                } label: {
                    Image(systemName: isStarred ? "star.fill" : "star")
                        .font(.system(size: 11))
                        .foregroundStyle(starForeground)
                }
                .buttonStyle(.plain)
                .help(isStarred ? "Убрать из избранного".localized : "В избранное".localized)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
            } else {
                Color.clear
                    .frame(width: 16, height: 16)
            }

            HStack(spacing: 10) {
                leadingContent
                trailingContent
            }
            .padding(.horizontal, 8)
            .padding(.vertical, isNarrow ? 2 : 5)
            .frame(height: isNarrow ? 26 : nil)
            .background {
                if isCurrent {
                    RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                        .fill(AMColor.accent)
                } else if isSelected {
                    RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                        .fill(AMColor.sidebarSelection.opacity(0.55))
                } else if hovering {
                    RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                if isPlayableLocally {
                    onPlay?(index ?? 0)
                }
            }
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
        // Fixed height (not minHeight) so LazyVStack can estimate row sizes
        // without materializing them — prevents gaps in long lists.
        .frame(height: showAlbum ? 46 : (showsArtist ? 40 : 32))
        .opacity(isPlayableLocally ? 1.0 : 0.45)
        .onHover { isInside in
            hoverTracker.isInside = isInside
            if isInside {
                if !ScrollGate.shared.isScrolling {
                    hovering = true
                }
            } else {
                if hovering {
                    hovering = false
                }
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
                    } else if hovering && isPlayableLocally {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(fgPrimary)
                    } else if let index {
                        Text("\(index + 1)")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(fgSecondary)
                    }
                }
                .frame(width: 22, height: isNarrow ? 20 : nil, alignment: .trailing)
                .contentShape(Rectangle())
                .onTapGesture {
                    if isCurrent {
                        app.player.togglePlayPause()
                    } else if isPlayableLocally {
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
                    } else if hovering && isPlayableLocally {
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
                    } else if isPlayableLocally {
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
            } else if hovering || isCachedLocally {
                Button {
                    if isCachedLocally {
                        Task { await app.removeFromCache(song) }
                    } else if !app.isOfflineSession {
                        app.cacheSong(song)
                    }
                } label: {
                    Image(systemName: isCachedLocally ? "checkmark.circle.fill" : "arrow.down.circle")
                        .font(.system(size: isNarrow ? 12 : 14))
                        .foregroundStyle(isCachedLocally ? AMColor.accent : Color.secondary)
                        .symbolEffect(.bounce, value: isCachedLocally)
                }
                .buttonStyle(.plain)
                .disabled(app.isOfflineSession && !isCachedLocally)
                .help(isCachedLocally ? "Удалить загрузку".localized : "Загрузить".localized)
                .accessibilityLabel(isCachedLocally ? "Удалить загрузку".localized
                                                    : (isDownloading ? "Загрузка".localized : "Загрузить".localized))
                .frame(width: isNarrow ? 16 : 18, height: isNarrow ? 16 : 18)
                .contentShape(Rectangle())
                .transition(.opacity)
                .accessibilityHidden(false)
            } else {
                Color.clear
                    .frame(width: isNarrow ? 16 : 18, height: isNarrow ? 16 : 18)
            }
            if let duration = song.duration {
                Text(Player.format(seconds: Double(duration)))
                    .font((isNarrow ? Font.caption2 : Font.caption).monospacedDigit())
                    .foregroundStyle(fgSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            if hovering {
                SongEllipsisMenu(song: song,
                                 foregroundStyle: isCurrent ? .white : .secondary,
                                 app: app,
                                 extraMenuItems: extraMenuItems,
                                 compact: isNarrow)
                    .transition(.opacity)
            } else {
                Color.clear
                    .frame(width: isNarrow ? 28 : 36, height: isNarrow ? 20 : 28)
            }
        }
    }
}

extension SongRow: Equatable {
    static func == (lhs: SongRow, rhs: SongRow) -> Bool {
        lhs.song.id == rhs.song.id
            && lhs.song.starred == rhs.song.starred
            && lhs.song.userRating == rhs.song.userRating
            && lhs.song.title == rhs.song.title
            && lhs.song.artist == rhs.song.artist
            && lhs.song.album == rhs.song.album
            && lhs.song.duration == rhs.song.duration
            && lhs.index == rhs.index
            && lhs.showAlbum == rhs.showAlbum
            && lhs.showsArtist == rhs.showsArtist
            && lhs.isCurrentOverride == rhs.isCurrentOverride
            && lhs.isSelected == rhs.isSelected
    }
}

/// Selection state manager for `SongRow`-based lists (album, playlist, smart playlist).
/// Handles Cmd+click (additive toggle) and plain click (replace with single item).
/// Pass `songs` for the full ordered list to support Shift+click range selection.
struct SongRowSelection {
    var ids: Set<SubsonicSong.ID> = []
    var anchor: SubsonicSong.ID?

    /// Toggle or replace selection based on current NSEvent modifier flags.
    mutating func toggle(_ id: SubsonicSong.ID, allSongs: [SubsonicSong]) {
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        if flags.contains(.command) {
            // Cmd+click: additive toggle
            if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
            anchor = id
        } else if flags.contains(.shift), let anchorId = anchor ?? ids.first,
                  let anchorIdx = allSongs.firstIndex(where: { $0.id == anchorId }),
                  let targetIdx = allSongs.firstIndex(where: { $0.id == id }) {
            // Shift+click: range from anchor to target
            let range = min(anchorIdx, targetIdx)...max(anchorIdx, targetIdx)
            ids = Set(allSongs[range].map(\.id))
        } else {
            // Plain click: if already the only selection, deselect; else select only this
            ids = ids == [id] ? [] : [id]
            anchor = ids.isEmpty ? nil : id
        }
    }

    func isSelected(_ id: SubsonicSong.ID) -> Bool { ids.contains(id) }

    func selectedSongs(from allSongs: [SubsonicSong]) -> [SubsonicSong] {
        allSongs.filter { ids.contains($0.id) }
    }
}
