import SwiftUI
import AppKit
import NavidromeClient

enum SongColumn: String, CaseIterable, Hashable, Identifiable {
    case title
    case cloud
    case duration
    case artist
    case album
    case albumArtist
    case genre
    case favorite
    case plays
    case year
    case composer
    case bitrate
    case rating
    case added

    var id: String { rawValue }

    static let defaults: Set<SongColumn> = [.title, .cloud, .duration, .artist, .album, .genre, .favorite, .plays]

    var title: String {
        switch self {
        case .title: return "Title".localized
        case .cloud: return "Cloud Download".localized
        case .duration: return "Time".localized
        case .artist: return "Artist".localized
        case .album: return "Album".localized
        case .albumArtist: return "Album artist".localized
        case .genre: return "Genre".localized
        case .favorite: return "Favorite".localized
        case .plays: return "Plays".localized
        case .year: return "Year".localized
        case .composer: return "Composer".localized
        case .bitrate: return "Bitrate".localized
        case .rating: return "Rating".localized
        case .added: return "Added".localized
        }
    }

    var headerText: Text {
        switch self {
        case .cloud:
            return Self.styledHeader(Text(Image(systemName: "icloud")))
        case .favorite:
            return Self.styledHeader(Text(Image(systemName: "star")))
        default:
            return Self.styledHeader(Text(title))
        }
    }

    private static func styledHeader(_ text: Text) -> Text {
        text.font(.caption).fontWeight(.regular).foregroundStyle(.secondary)
    }

    var alignment: TableColumnAlignment {
        switch self {
        case .duration, .plays, .year, .bitrate: return .trailing
        case .cloud, .favorite: return .center
        default: return .leading
        }
    }

    var contentAlignment: Alignment {
        switch self {
        case .duration, .plays, .year, .bitrate: return .trailing
        case .cloud, .favorite: return .center
        default: return .leading
        }
    }

    var comparator: KeyPathComparator<SubsonicSong> {
        switch self {
        case .title: return KeyPathComparator(\.title)
        case .cloud: return KeyPathComparator(\.path)
        case .duration: return KeyPathComparator(\.duration)
        case .artist: return KeyPathComparator(\.artist)
        case .album: return KeyPathComparator(\.album)
        case .albumArtist: return KeyPathComparator(\.albumArtist)
        case .genre: return KeyPathComparator(\.genre)
        case .favorite: return KeyPathComparator(\.starred)
        case .plays: return KeyPathComparator(\.playCount)
        case .year: return KeyPathComparator(\.year)
        case .composer: return KeyPathComparator(\.composer)
        case .bitrate: return KeyPathComparator(\.bitRate)
        case .rating: return KeyPathComparator(\.userRating)
        case .added: return KeyPathComparator(\.created)
        }
    }

    var minWidth: CGFloat {
        switch self {
        case .cloud, .favorite: return 24
        case .duration: return 44
        case .plays: return 40
        default: return 50
        }
    }

    var idealWidth: CGFloat {
        switch self {
        case .cloud, .favorite: return 26
        case .duration: return 56
        case .plays: return 60
        default: return 140
        }
    }

    var maxWidth: CGFloat {
        switch self {
        case .cloud, .favorite: return 28
        case .duration: return 80
        case .plays: return 90
        default: return 400
        }
    }
}

/// The rows handed to `Table` are a lazy window (`displayedSongs`: a prefix of
/// `songs`, grown as its tail becomes visible). SwiftUI's `Table` materializes
/// every row given to it on the main thread, so feeding it all 15k rows at once
/// freezes the window for a minute; a small window keeps the NSTableView cheap
/// while scrolling. The full `songs` array stays the source of truth for
/// selection, context menus, and playback.
struct SongTable: View {
    let songs: [SubsonicSong]
    @Binding var sortOrder: [KeyPathComparator<SubsonicSong>]
    @Binding var columnCustomization: TableColumnCustomization<SubsonicSong>

    @Environment(AppState.self) private var app

    private let pageSize = 500

    @State private var displayedCount: Int = 0
    @State private var displayedSongsCache: [SubsonicSong] = []
    private var displayedSongs: [SubsonicSong] { displayedSongsCache }

    private func updateDisplayedSongs() {
        displayedSongsCache = Array(songs.prefix(displayedCount))
    }

    @State private var selection = Set<SubsonicSong.ID>()
    @State private var hoverManager = RowHoverManager()

    private func prefetchMoreIfNeeded() {
        guard displayedCount > 0, displayedCount < songs.count else { return }
        displayedCount = min(displayedCount + pageSize, songs.count)
        updateDisplayedSongs()
    }

    var body: some View {
        let currentSongID = app.player.currentSong?.id

        Table(displayedSongs, selection: $selection, sortOrder: $sortOrder,
              columnCustomization: $columnCustomization) {
            TableColumnForEach(SongColumn.allCases) { (column: SongColumn) in
                TableColumn(column.headerText, sortUsing: column.comparator) { (song: SubsonicSong) in
                    SongColumnCell(
                        column: column,
                        song: song,
                        app: app,
                        hoverState: hoverManager.state(for: song.id),
                        isCurrent: song.id == currentSongID
                    )
                }
                .width(min: column.minWidth, ideal: column.idealWidth, max: column.maxWidth)
                .alignment(column.alignment)
                .customizationID(column.id)
            }
        }
        .onAppear {
            displayedCount = min(pageSize, songs.count)
            updateDisplayedSongs()
        }
        .onChange(of: songs) {
            displayedCount = max(displayedCount, min(pageSize, songs.count))
            updateDisplayedSongs()
        }
        .onChange(of: sortOrder) {
            hoverManager.clearHover()
            displayedCount = min(pageSize, songs.count)
            updateDisplayedSongs()
        }
        .tint(AMColor.sidebarSelection)
        .background(
            TableTweaks(
                songCount: displayedSongs.count,
                hoverManager: hoverManager,
                rowHeight: 22,
                onPrefetch: { prefetchMoreIfNeeded() },
                songIDAtRow: { [displayedSongs] row in
                    guard row >= 0 && row < displayedSongs.count else { return nil }
                    return displayedSongs[row].id
                }
            )
        )
        .contextMenu(forSelectionType: SubsonicSong.ID.self) { ids in
            if let id = ids.first, let song = songs.first(where: { $0.id == id }) {
                SongContextMenu(song: song, songs: songs, selection: ids, app: app)
            }
        } primaryAction: { ids in
            play(ids)
        }
    }

    private func play(_ ids: Set<SubsonicSong.ID>) {
        let run = songs.filter { ids.contains($0.id) }
        guard let first = run.first else { return }
        app.play(first, in: songs)
    }

    fileprivate static func addedDateText(_ iso: String?) -> String {
        SubsonicDate.longDate(iso) ?? "—"
    }
}

private struct SongContextMenu: View {
    let song: SubsonicSong
    let songs: [SubsonicSong]
    let selection: Set<SubsonicSong.ID>
    let app: AppState

    private var ids: Set<SubsonicSong.ID> { selection.isEmpty ? [song.id] : selection }

    var body: some View {
        SongActionItems(
            app: app,
            song: song,
            selection: songs.filter { ids.contains($0.id) },
            onPlay: {
                let run = songs.filter { ids.contains($0.id) }
                app.play(run.first ?? song, in: songs)
            }
        )
    }
}

private struct SongColumnCell: View {
    let column: SongColumn
    let song: SubsonicSong
    let app: AppState
    let hoverState: RowHoverState
    let isCurrent: Bool

    var body: some View {
        cellContent
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: column.contentAlignment)
    }

    @ViewBuilder
    private var cellContent: some View {
        switch column {
        case .title:
            HStack(spacing: 6) {
                if isCurrent {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(AMColor.accent)
                }
                Text(song.displayTitle)
                    .foregroundStyle(isCurrent ? AMColor.accent : .primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                TitleEllipsisButton(song: song, app: app)
            }
            .padding(.leading, 8)
        case .cloud:
            CloudCell(song: song, app: app)
        case .duration:
            if let duration = song.duration {
                Text(Player.format(seconds: Double(duration)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        case .artist:
            Text(song.artist ?? "")
                .foregroundStyle(.secondary)
                .lineLimit(1)
        case .album:
            Text(song.album ?? "")
                .foregroundStyle(.secondary)
                .lineLimit(1)
        case .albumArtist:
            Text(song.albumArtist ?? "")
                .foregroundStyle(.secondary)
                .lineLimit(1)
        case .genre:
            Text(song.genre ?? "")
                .foregroundStyle(.secondary)
                .lineLimit(1)
        case .favorite:
            FavoriteCell(song: song, app: app, hoverState: hoverState)
        case .plays:
            Text(song.playCount.map(String.init) ?? "")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        case .year:
            Text(song.year.map(String.init) ?? "")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        case .composer:
            Text(song.composer ?? "")
                .foregroundStyle(.secondary)
                .lineLimit(1)
        case .bitrate:
            Text(song.bitRate.map { "\($0) kbps" } ?? "")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        case .rating:
            if app.effectiveRating(for: song) > 0 {
                RatingStars(song: song, app: app, size: 10, spacing: 2)
            }
        case .added:
            Text(SongTable.addedDateText(song.created))
                .foregroundStyle(.secondary)
        }
    }
}

private struct TitleEllipsisButton: View {
    let song: SubsonicSong
    let app: AppState

    var body: some View {
        SongEllipsisMenu(
            song: song,
            foregroundStyle: AMColor.accent,
            app: app,
            compact: true,
            side: 16
        )
    }
}

private struct FavoriteCell: View {
    let song: SubsonicSong
    let app: AppState
    let hoverState: RowHoverState

    var body: some View {
        TrackFavoriteButton(song: song, app: app, isHovered: hoverState.isHovered, size: 16)
    }
}

private struct CloudCell: View {
    let song: SubsonicSong
    let app: AppState

    var body: some View {
        TrackDownloadButton(song: song, app: app, style: .tableCell, size: 16)
    }
}
