import SwiftUI
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

    var comparator: KeyPathComparator<SubsonicSong> {
        switch self {
        case .title: return KeyPathComparator(\.title)
        case .cloud: return KeyPathComparator(\.path)
        case .duration: return KeyPathComparator(\.duration)
        case .artist: return KeyPathComparator(\.artist)
        case .album: return KeyPathComparator(\.album)
        case .albumArtist: return KeyPathComparator(\.resolvedAlbumArtist)
        case .genre: return KeyPathComparator(\.genre)
        case .favorite: return KeyPathComparator(\.starred)
        case .plays: return KeyPathComparator(\.playCount)
        case .year: return KeyPathComparator(\.year)
        case .composer: return KeyPathComparator(\.resolvedComposer)
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

struct SongTable: View {
    let songs: [SubsonicSong]
    @Binding var sortOrder: [KeyPathComparator<SubsonicSong>]
    @Binding var columnCustomization: TableColumnCustomization<SubsonicSong>

    @Environment(AppState.self) private var app

    private var displayedSongs: [SubsonicSong] { songs }

    @State private var selection = Set<SubsonicSong.ID>()
    @State private var hoverManager = RowHoverManager()

    private func dragPayload(for song: SubsonicSong) -> TrackDragPayload {
        if selection.contains(song.id) && selection.count > 1 {
            let orderedIDs = displayedSongs.filter { selection.contains($0.id) }.map(\.id)
            if orderedIDs.count > 1 {
                return .songs(orderedIDs)
            }
        }
        return .song(song.id, exportInfo: app.exportInfo(for: song, allowRemote: false))
    }

    var body: some View {
        let currentSongID = app.player.currentSong?.id

        Table(of: SubsonicSong.self, selection: $selection, sortOrder: $sortOrder,
              columnCustomization: $columnCustomization) {
            firstColumns(currentSongID: currentSongID)
            secondColumns()
        } rows: {
            ForEach(displayedSongs) { song in
                TableRow(song)
                    .draggable(dragPayload(for: song))
            }
        }
        .onChange(of: songs) {
            hoverManager.reset()
        }
        .onChange(of: sortOrder) {
            hoverManager.reset()
        }
        .onDisappear {
            hoverManager.reset()
        }
        .tint(AMColor.sidebarSelection)
        .background(
            TableTweaks(
                songCount: displayedSongs.count,
                totalCount: songs.count,
                hoverManager: hoverManager,
                rowHeight: 22,
                onPrefetch: nil,
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

    @TableColumnBuilder<SubsonicSong, KeyPathComparator<SubsonicSong>>
    private func firstColumns(currentSongID: SubsonicSong.ID?) -> some TableColumnContent<SubsonicSong, KeyPathComparator<SubsonicSong>> {
        titleColumn(currentSongID: currentSongID)
        cloudColumn()
        numericColumn(.duration) { $0.duration.map { Player.format(seconds: Double($0)) } ?? "" }
        textColumn(.artist) { $0.artist ?? "" }
        textColumn(.album) { $0.album ?? "" }
        textColumn(.albumArtist) { $0.resolvedAlbumArtist }
        textColumn(.genre) { $0.genre ?? "" }
    }

    @TableColumnBuilder<SubsonicSong, KeyPathComparator<SubsonicSong>>
    private func secondColumns() -> some TableColumnContent<SubsonicSong, KeyPathComparator<SubsonicSong>> {
        favoriteColumn()
        numericColumn(.plays) { $0.playCount.map(String.init) ?? "" }
        numericColumn(.year) { $0.year.map(String.init) ?? "" }
        textColumn(.composer) { $0.resolvedComposer ?? "" }
        numericColumn(.bitrate) { $0.bitRate.map { "\($0) kbps" } ?? "" }
        ratingColumn()
        textColumn(.added) { SongTable.addedDateText($0.created) }
    }

    @TableColumnBuilder<SubsonicSong, KeyPathComparator<SubsonicSong>>
    private func titleColumn(
        currentSongID: SubsonicSong.ID?
    ) -> some TableColumnContent<SubsonicSong, KeyPathComparator<SubsonicSong>> {
        let column = SongColumn.title
        TableColumn(column.headerText, sortUsing: column.comparator) { (song: SubsonicSong) in
            TitleColumnCell(
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

    @TableColumnBuilder<SubsonicSong, KeyPathComparator<SubsonicSong>>
    private func cloudColumn() -> some TableColumnContent<SubsonicSong, KeyPathComparator<SubsonicSong>> {
        let column = SongColumn.cloud
        TableColumn(column.headerText, sortUsing: column.comparator) { (song: SubsonicSong) in
            CloudCell(song: song, app: app)
        }
        .width(min: column.minWidth, ideal: column.idealWidth, max: column.maxWidth)
        .alignment(column.alignment)
        .customizationID(column.id)
    }

    @TableColumnBuilder<SubsonicSong, KeyPathComparator<SubsonicSong>>
    private func favoriteColumn() -> some TableColumnContent<SubsonicSong, KeyPathComparator<SubsonicSong>> {
        let column = SongColumn.favorite
        TableColumn(column.headerText, sortUsing: column.comparator) { (song: SubsonicSong) in
            FavoriteCell(song: song, app: app, hoverState: hoverManager.state(for: song.id))
        }
        .width(min: column.minWidth, ideal: column.idealWidth, max: column.maxWidth)
        .alignment(column.alignment)
        .customizationID(column.id)
    }

    @TableColumnBuilder<SubsonicSong, KeyPathComparator<SubsonicSong>>
    private func ratingColumn() -> some TableColumnContent<SubsonicSong, KeyPathComparator<SubsonicSong>> {
        let column = SongColumn.rating
        TableColumn(column.headerText, sortUsing: column.comparator) { (song: SubsonicSong) in
            if app.effectiveRating(for: song) > 0 {
                RatingStars(song: song, app: app, size: 10, spacing: 2)
            }
        }
        .width(min: column.minWidth, ideal: column.idealWidth, max: column.maxWidth)
        .alignment(column.alignment)
        .customizationID(column.id)
    }

    @TableColumnBuilder<SubsonicSong, KeyPathComparator<SubsonicSong>>
    private func textColumn(
        _ column: SongColumn,
        value: @escaping (SubsonicSong) -> String
    ) -> some TableColumnContent<SubsonicSong, KeyPathComparator<SubsonicSong>> {
        TableColumn(column.headerText, sortUsing: column.comparator) { (song: SubsonicSong) in
            Text(value(song))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .width(min: column.minWidth, ideal: column.idealWidth, max: column.maxWidth)
        .alignment(column.alignment)
        .customizationID(column.id)
    }

    @TableColumnBuilder<SubsonicSong, KeyPathComparator<SubsonicSong>>
    private func numericColumn(
        _ column: SongColumn,
        value: @escaping (SubsonicSong) -> String
    ) -> some TableColumnContent<SubsonicSong, KeyPathComparator<SubsonicSong>> {
        TableColumn(column.headerText, sortUsing: column.comparator) { (song: SubsonicSong) in
            Text(value(song))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .width(min: column.minWidth, ideal: column.idealWidth, max: column.maxWidth)
        .alignment(column.alignment)
        .customizationID(column.id)
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

private struct TitleColumnCell: View {
    let song: SubsonicSong
    let app: AppState
    let hoverState: RowHoverState
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 6) {
            if isCurrent {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(AMColor.accent)
            }
            Text(song.displayTitle)
                .foregroundStyle(isCurrent ? AMColor.accent : .primary)
                .lineLimit(1)
            if song.isExplicit {
                ExplicitBadge()
            }
            Spacer(minLength: 4)
            TitleEllipsisButton(song: song, app: app, hoverState: hoverState)
        }
        .padding(.leading, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct TitleEllipsisButton: View {
    let song: SubsonicSong
    let app: AppState
    let hoverState: RowHoverState

    var body: some View {
        if hoverState.isHovered {
            SongEllipsisMenu(
                song: song,
                foregroundStyle: AMColor.accent,
                app: app,
                compact: true,
                side: 16
            )
        } else {
            Color.clear.frame(width: 16, height: 16)
        }
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
