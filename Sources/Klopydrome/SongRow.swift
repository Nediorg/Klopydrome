import AppKit
import SwiftUI
import NavidromeClient

struct SongRow: View {
    let song: SubsonicSong
    var index: Int?
    var showAlbum = true
    var showsArtist = false
    var isCurrentOverride: Bool?
    var playlist: PlaylistSummary?
    var playlistIndex: Int?
    var extraActions: [SongMenuExtraAction] = []
    var onPlay: ((Int) -> Void)?
    var isSelected = false
    var resolveSelection: (() -> [SubsonicSong])?
    var onSelect: (() -> Void)?

    @Environment(AppState.self) private var app
    @State private var hovering = false
    @State private var hoverTracker = HoverTracker()

    private var isCurrent: Bool { isCurrentOverride ?? (app.player.currentSong?.id == song.id) }
    private var fgPrimary: Color { isCurrent ? AMColor.accent : .primary }
    private var fgSecondary: Color { AMColor.secondaryText }
    private var isCachedLocally: Bool { app.isCached(song) }
    private var isCurrentPlaying: Bool { isCurrent && app.player.isPlaying }
    private var isPlayableLocally: Bool { !app.isOfflineSession || isCachedLocally }
    private var isNarrow: Bool { !showAlbum && !showsArtist }
    private var rowCornerRadius: CGFloat { isNarrow ? 4 : 6 }

    private var actionTargets: [SubsonicSong] {
        guard isSelected, let resolve = resolveSelection else { return [song] }
        let resolved = resolve()
        return resolved.count > 1 ? resolved : [song]
    }

    var body: some View {
        HStack(spacing: 6) {
            TrackFavoriteButton(song: song, app: app, isHovered: hovering, size: 16)

            HStack(spacing: 10) {
                leadingContent
                trailingContent
            }
            .padding(.leading, showAlbum ? 5 : 8)
            .padding(.trailing, 8)
            .padding(.vertical, isNarrow ? 2 : 5)
            .frame(height: isNarrow ? 26 : nil)
            .background {
                if isSelected {
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
                ForEach(extraActions, id: \.title) { extra in
                    Button(extra.title) { extra.action() }
                }
                SongActionItems(
                    app: app,
                    song: song,
                    playlist: playlist,
                    playlistIndex: playlistIndex,
                    selection: actionTargets,
                    onPlay: onPlay.map { play in { play(index ?? 0) } }
                )
            }
        }
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
        .animation(.snappy(duration: 0.12), value: isSelected)
    }

    @ViewBuilder
    private var leadingContent: some View {
        HStack(spacing: showAlbum ? 8 : 10) {
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
                    .font(AMFont.rowTitle)
                    .foregroundStyle(fgPrimary)
                    .lineLimit(1)
                if showAlbum {
                    Text(song.displaySubtitle)
                        .font(AMFont.rowSubtitle)
                        .foregroundStyle(fgSecondary)
                        .lineLimit(1)
                } else if showsArtist, let artist = song.artist {
                    Text(artist)
                        .font(AMFont.rowSubtitle)
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
            TrackDownloadButton(
                song: song,
                app: app,
                isHovered: hovering,
                style: .roundedCircle,
                size: isNarrow ? 16 : 18
            )
            if let duration = song.duration {
                Text(Player.format(seconds: Double(duration)))
                    .font((isNarrow ? Font.caption2 : Font.caption).monospacedDigit())
                    .foregroundStyle(fgSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            SongEllipsisMenu(
                song: song,
                selection: actionTargets,
                resolveSelection: isSelected ? resolveSelection : nil,
                foregroundStyle: .secondary,
                app: app,
                playlist: playlist,
                playlistIndex: playlistIndex,
                extraActions: extraActions,
                compact: isNarrow
            )
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
            && lhs.playlist?.id == rhs.playlist?.id
            && lhs.playlistIndex == rhs.playlistIndex
    }
}

struct SongRowSelection {
    var ids: Set<SubsonicSong.ID> = []
    var anchor: SubsonicSong.ID?

    mutating func toggle(_ id: SubsonicSong.ID, allSongs: [SubsonicSong]) {
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        if flags.contains(.command) {
            if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
            anchor = id
        } else if flags.contains(.shift), let anchorId = anchor ?? ids.first,
                  let anchorIdx = allSongs.firstIndex(where: { $0.id == anchorId }),
                  let targetIdx = allSongs.firstIndex(where: { $0.id == id }) {
            let range = min(anchorIdx, targetIdx)...max(anchorIdx, targetIdx)
            ids = Set(allSongs[range].map(\.id))
        } else {
            ids = ids == [id] ? [] : [id]
            anchor = ids.isEmpty ? nil : id
        }
    }

    func isSelected(_ id: SubsonicSong.ID) -> Bool { ids.contains(id) }

    func selectedSongs(from allSongs: [SubsonicSong]) -> [SubsonicSong] {
        allSongs.filter { ids.contains($0.id) }
    }
}
