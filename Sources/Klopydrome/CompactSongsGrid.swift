import SwiftUI
import NavidromeClient

/// An item pairing a track with its global index in the source songs array.
struct CompactSongItem {
    let song: SubsonicSong
    let globalIndex: Int

    static func columns(from songs: [SubsonicSong], columnSize: Int = 3) -> [[CompactSongItem]] {
        guard !songs.isEmpty else { return [] }
        return stride(from: 0, to: songs.count, by: columnSize).map { colBase in
            let end = min(colBase + columnSize, songs.count)
            return (colBase..<end).map { globalIdx in
                CompactSongItem(song: songs[globalIdx], globalIndex: globalIdx)
            }
        }
    }
}

/// A 3-column tabular song section matching Apple Music Sequoia.
///
/// In collapsed mode, it renders as a horizontal carousel (`ScrollView(.horizontal)`),
/// scrolling columns of strictly 3 songs side-by-side.
///
/// In expanded mode, it stacks 3x3 blocks downward in the page without reordering.
/// Any remainder songs are balanced evenly across the 3 columns into available slots.
struct CompactSongsSection: View {
    let title: String
    var titleFont: Font = .title3.bold()
    let songs: [SubsonicSong]
    var columnWidth: CGFloat = 280
    var subtitle: ((SubsonicSong) -> String?)?

    @Environment(AppState.self) private var app
    @State private var expanded = false
    @State private var expandedLimit = 45

    private let maxCarouselColumns = 10

    /// In collapsed mode (carousel), columns are strictly chunked into 3 songs each.
    private var carouselColumns: [[CompactSongItem]] {
        Array(CompactSongItem.columns(from: songs).prefix(maxCarouselColumns))
    }

    /// Can expand if there is more than 1 full 3x3 block (more than 9 songs).
    private var canExpand: Bool {
        songs.count > 9
    }

    private var songsIdentity: String {
        "\(songs.count)-\(songs.first?.id ?? "")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if expanded {
                expandedGrid
            } else {
                collapsedCarousel
            }
        }
        .onChange(of: songsIdentity) {
            expanded = false
            expandedLimit = 45
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button {
                if canExpand {
                    withAnimation(Motion.spring(Motion.expand)) {
                        expanded.toggle()
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(title)
                        .font(titleFont)
                    if canExpand {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canExpand)
            .help(expanded ? "Свернуть".localized : "Раскрыть".localized)
            .accessibilityLabel(expanded ? "Свернуть".localized : "Раскрыть".localized)
        }
    }

    /// Horizontal carousel of strictly 3-song columns.
    private var collapsedCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(Array(carouselColumns.enumerated()), id: \.offset) { _, colItems in
                    CompactSongColumn(
                        items: colItems,
                        allSongs: songs,
                        subtitle: subtitle
                    )
                    .frame(width: columnWidth)
                }
            }
            .padding(.vertical, 4)
        }
        .scrollClipDisabled()
    }

    /// Continuous 3-column layout without vertical block gaps and with dividers between all songs.
    private var expandedGrid: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(0..<3, id: \.self) { columnIndex in
                    let colItems = expandedSongsForColumn(columnIndex)
                    if !colItems.isEmpty {
                        CompactSongColumn(
                            items: colItems,
                            allSongs: songs,
                            subtitle: subtitle
                        )
                        .frame(maxWidth: .infinity)
                    } else {
                        Spacer().frame(maxWidth: .infinity)
                    }
                }
            }

            if songs.count > expandedLimit {
                Button {
                    expandedLimit = min(expandedLimit + 45, songs.count)
                } label: {
                    HStack(spacing: 6) {
                        Text("Показать ещё".localized)
                            .font(.callout.weight(.medium))
                        Image(systemName: "chevron.down")
                            .font(.caption)
                    }
                    .foregroundStyle(AMColor.accent)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 4)
            }
        }
    }

    /// Flattens songs for a screen column (0, 1, or 2) in expanded mode:
    /// Full 3x3 blocks (9 songs) place 3 songs into each column.
    /// The remainder (< 9 songs) is balanced evenly across columns into available slots.
    private func expandedSongsForColumn(_ columnIndex: Int) -> [CompactSongItem] {
        guard !songs.isEmpty else { return [] }
        let visibleCount = min(expandedLimit, songs.count)
        var result: [CompactSongItem] = []

        let fullBlockCount = visibleCount / 9
        for blockIdx in 0..<fullBlockCount {
            let base = blockIdx * 9 + columnIndex * 3
            for offset in 0..<3 {
                let globalIdx = base + offset
                result.append(CompactSongItem(song: songs[globalIdx], globalIndex: globalIdx))
            }
        }

        let remainder = visibleCount % 9
        if remainder > 0 {
            let remBaseIndex = fullBlockCount * 9
            let remBase = remainder / 3
            let remExtra = remainder % 3
            let col0 = remBase + (remExtra > 0 ? 1 : 0)
            let col1 = remBase + (remExtra > 1 ? 1 : 0)
            let col2 = remBase
            let counts = [col0, col1, col2]

            var startOffset = 0
            for idx in 0..<columnIndex {
                startOffset += counts[idx]
            }
            let countForThisColumn = counts[columnIndex]
            for offset in 0..<countForThisColumn {
                let globalIdx = remBaseIndex + startOffset + offset
                result.append(CompactSongItem(song: songs[globalIdx], globalIndex: globalIdx))
            }
        }

        return result
    }
}

// MARK: - Column & Row

struct CompactSongColumn: View {
    let items: [CompactSongItem]
    let allSongs: [SubsonicSong]
    var subtitle: ((SubsonicSong) -> String?)?
    @Environment(AppState.self) private var app

    var body: some View {
        let currentID = app.player.currentSong?.id
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.globalIndex) { offset, item in
                CompactSongRow(
                    song: item.song,
                    subtitle: subtitle?(item.song),
                    isCurrent: currentID == item.song.id,
                    onPlay: {
                        app.play(allSongs, at: item.globalIndex)
                    }
                )
                .equatable()

                if offset < items.count - 1 {
                    Divider()
                        .padding(.leading, 50)
                        .padding(.trailing, 6)
                        .opacity(0.4)
                }
            }
        }
    }
}

struct CompactSongRow: View {
    let song: SubsonicSong
    var subtitle: String?
    let isCurrent: Bool
    let onPlay: () -> Void

    @Environment(AppState.self) private var app
    @State private var hovering = false
    @State private var hoverTracker = HoverTracker()

    private var isPlaying: Bool { isCurrent && app.player.isPlaying }

    private var isStarred: Bool { app.isStarred(song) }

    private var displaySubtitle: String? {
        if let subtitle, !subtitle.isEmpty { return subtitle }
        return song.artist
    }

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
            .contentShape(Rectangle())
            .onTapGesture {
                if isCurrent {
                    app.player.togglePlayPause()
                } else {
                    onPlay()
                }
            }

            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(song.displayTitle)
                        .font(.callout)
                        .lineLimit(1)
                        .foregroundStyle(isCurrent ? AMColor.accent : .primary)
                    if let sub = displaySubtitle, !sub.isEmpty {
                        Text(sub)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                Button {
                    app.toggleStar(song)
                } label: {
                    Image(systemName: isStarred ? "star.fill" : "star")
                        .font(.system(size: 11))
                        .foregroundStyle(isStarred ? AMColor.accent : Color.secondary)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isStarred ? "Убрать из избранного".localized : "В избранное".localized)
                .opacity(isStarred ? 1 : (hovering ? 1 : 0))
                .allowsHitTesting(hovering || isStarred)

                if hovering {
                    Menu {
                        SongActionItems(app: app, song: song, onPlay: onPlay)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
                    .fixedSize()
                    .transition(.opacity)
                } else {
                    Color.clear
                        .frame(width: 22, height: 22)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.06 : 0))
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onPlay() }
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
        .animation(.snappy(duration: 0.12), value: hovering)
        .contextMenu {
            SongActionItems(app: app, song: song, onPlay: onPlay)
        }
    }
}

extension CompactSongRow: Equatable {
    static func == (lhs: CompactSongRow, rhs: CompactSongRow) -> Bool {
        lhs.song.id == rhs.song.id
            && lhs.song.starred == rhs.song.starred
            && lhs.song.userRating == rhs.song.userRating
            && lhs.song.title == rhs.song.title
            && lhs.song.artist == rhs.song.artist
            && lhs.song.album == rhs.song.album
            && lhs.song.duration == rhs.song.duration
            && lhs.subtitle == rhs.subtitle
            && lhs.isCurrent == rhs.isCurrent
    }
}
