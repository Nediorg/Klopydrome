import SwiftUI
import AppKit
import NavidromeClient

/// Table column identifiers for the Songs tab.
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

    /// Columns shown by default (matches Apple Music layout).
    static let defaults: Set<SongColumn> = [.title, .cloud, .duration, .artist, .album, .genre, .favorite, .plays]

    var title: String {
        switch self {
        case .title: return "Название".localized
        case .cloud: return "Загрузка в облако".localized
        case .duration: return "Время".localized
        case .artist: return "Артист".localized
        case .album: return "Альбом".localized
        case .albumArtist: return "Исполнитель альбома".localized
        case .genre: return "Жанр".localized
        case .favorite: return "Избранное".localized
        case .plays: return "Прослушиваний".localized
        case .year: return "Год".localized
        case .composer: return "Композитор".localized
        case .bitrate: return "Битрейт".localized
        case .rating: return "Рейтинг".localized
        case .added: return "Добавлено".localized
        }
    }

    /// Header text/icon for TableColumn. Cloud and favorite show SF symbols instead of text.
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

    /// Apple Music header look: small, regular weight, secondary colour.
    /// NOTE: SwiftUI `Table` may ignore some of these on certain macOS builds;
    /// if so, the header must be restyled via NSTableHeaderView instead.
    private static func styledHeader(_ text: Text) -> Text {
        text.font(.system(size: 11)).fontWeight(.regular).foregroundStyle(.secondary)
    }

    /// Numeric columns are right-aligned (header included) like Apple Music;
    /// icon columns are centred. Requires macOS 14.4+ (`TableColumnAlignment`).
    var alignment: TableColumnAlignment {
        switch self {
        case .duration, .plays, .year, .bitrate: return .trailing
        case .cloud, .favorite: return .center
        default: return .leading
        }
    }

    /// Content alignment for SwiftUI cell views inside the column.
    var contentAlignment: Alignment {
        switch self {
        case .duration, .plays, .year, .bitrate: return .trailing
        case .cloud, .favorite: return .center
        default: return .leading
        }
    }

    /// Sort comparator for this column's key path.
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

/// Sortable, configurable table of songs (Apple Music Songs tab). Column
/// visibility is handled natively via `columnCustomization` — the user
/// right-clicks a column header to show/hide/reorder columns.
///
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

    /// Rows per render-window step. 500 rows provides 11,000pt of scroll runway,
    /// preventing hitches during fast trackpad flings.
    private let pageSize = 500

    /// Render window size; first `displayedCount` rows of `songs` are shown.
    @State private var displayedCount: Int = 0
    @State private var displayedSongsCache: [SubsonicSong] = []
    private var displayedSongs: [SubsonicSong] { displayedSongsCache }

    private func updateDisplayedSongs() {
        displayedSongsCache = Array(songs.prefix(displayedCount))
    }

    /// Tracks the selected rows so left-click selects and multi-select works.
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
            // Start with a full page instead of an empty table until the
            // first scroll grows the window.
            displayedCount = min(pageSize, songs.count)
            updateDisplayedSongs()
        }
        .onChange(of: songs) {
            displayedCount = max(displayedCount, min(pageSize, songs.count))
            updateDisplayedSongs()
        }
        .onChange(of: sortOrder) {
            // Reset to a single page on re-sort: `Table` re-sorts the handed-in
            // array synchronously, and if the window had grown to the whole
            // library that would re-materialize every row on the main thread —
            // the exact freeze we're avoiding. `SongsView` re-sorts the full
            // library off-main and lands a fresh page.
            hoverManager.clearHover()
            displayedCount = min(pageSize, songs.count)
            updateDisplayedSongs()
        }
        // Light-gray selection accent (matches the sidebar) instead of the red
        // accent, so a selected row reads as a neutral highlight, not a colored one.
        .tint(AMColor.sidebarSelection)
        // Apple Music-style 22 pt row height plus native AppKit hover tracking
        // over the backing NSTableView.
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
        // `contextMenu(forSelectionType:)` auto-selects the clicked row (and lets
        // Cmd/Shift multi-select), so the menu always has a concrete target.
        // Pass `ids` (the current right-clicked selection) rather than the `selection`
        // @State, which may lag by one frame if the click didn't extend an existing selection.
        .contextMenu(forSelectionType: SubsonicSong.ID.self) { ids in
            if let id = ids.first, let song = songs.first(where: { $0.id == id }) {
                SongContextMenu(song: song, songs: songs, selection: ids, app: app)
            }
        } primaryAction: { ids in
            // Double-click plays the whole contiguous run starting at the row.
            play(ids)
        }
    }

    /// Plays the selected rows in table order (multi-select), or just the one
    /// row if a single row is selected.
    private func play(_ ids: Set<SubsonicSong.ID>) {
        let run = songs.filter { ids.contains($0.id) }
        guard let first = run.first, let idx = songs.firstIndex(where: { $0.id == first.id }) else { return }
        app.play(songs, at: idx)
    }

    fileprivate static func addedDateText(_ iso: String?) -> String {
        SubsonicDate.longDate(iso) ?? "—"
    }
}

/// Populates a song's right-click menu in the Songs table. Shared with other
/// lists (albums, playlists) via `Components.SongRow`, this version plays from
/// the surrounding table context so "Слушать" also works when the row wasn't
/// pre-selected.
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
                // Play the selected rows in table order; single selection plays its run.
                let run = songs.filter { ids.contains($0.id) }
                if let first = run.first, let idx = songs.firstIndex(where: { $0.id == first.id }) {
                    app.play(songs, at: idx)
                } else {
                    app.play([song])
                }
            }
        )
    }
}

/// Uniform cell for a Song table column; renders per column type so every
/// `TableColumn` shares one content type (required by `TableColumnForEach`).
/// Takes `app` explicitly (not from `@Environment`) because Table cells are
/// hosted in an NSTableView that doesn't reliably propagate the environment.
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
                TitleEllipsisButton(song: song, app: app, hoverState: hoverState)
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

/// Ellipsis actions button, gated by row hover to avoid building thousands of
/// menus during fast scroll.
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

/// Isolated favorite button cell so only this small view re-renders on hover changes.
private struct FavoriteCell: View {
    let song: SubsonicSong
    let app: AppState
    let hoverState: RowHoverState

    private var isStarred: Bool {
        app.isStarred(song)
    }

    var body: some View {
        Button {
            app.toggleStar(song)
        } label: {
            Image(systemName: isStarred ? "star.fill" : "star")
                .font(.system(size: 11))
                .foregroundStyle(AMColor.accent)
                .opacity(isStarred || hoverState.isHovered ? 1 : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isStarred ? "Убрать из избранного".localized : "В избранное".localized)
    }
}

/// Isolated cloud/download status cell so caching and downloading state changes
/// only re-render this cell rather than the entire row.
private struct CloudCell: View {
    let song: SubsonicSong
    let app: AppState

    private var isDownloading: Bool {
        app.downloadingSongIDs.contains(song.id)
    }

    private var isCachedLocally: Bool {
        app.isCached(song)
    }

    var body: some View {
        HStack {
            Spacer()
            if isDownloading {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 14, height: 14)
                    .help("Загрузка…".localized)
            } else if isCachedLocally {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.secondary)
                    .help("Загружено".localized)
            } else if !app.isOfflineSession {
                Button {
                    app.cacheSong(song)
                } label: {
                    Image(systemName: "arrow.down.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)
                .help("Загрузить".localized)
            }
            Spacer()
        }
    }
}
