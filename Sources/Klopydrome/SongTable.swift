import SwiftUI
import NavidromeClient

/// Table column identifiers for the Songs tab.
enum SongColumn: String, CaseIterable, Hashable, Identifiable {
    case title, artist, album, duration, year, genre, bitrate, rating, plays, added

    var id: String { rawValue }

    /// Columns shown by default (title is always visible).
    static let defaults: Set<SongColumn> = [.artist, .album, .duration, .rating]

    var title: String {
        switch self {
        case .title: return "Название"
        case .artist: return "Артист"
        case .album: return "Альбом"
        case .duration: return "Длительность"
        case .year: return "Год"
        case .genre: return "Жанр"
        case .bitrate: return "Битрейт"
        case .rating: return "Рейтинг"
        case .plays: return "Воспроизведено"
        case .added: return "Добавлено"
        }
    }

    /// Sort comparator for this column's key path.
    var comparator: KeyPathComparator<SubsonicSong> {
        switch self {
        case .title: return KeyPathComparator(\.title)
        case .artist: return KeyPathComparator(\.artist)
        case .album: return KeyPathComparator(\.album)
        case .duration: return KeyPathComparator(\.duration)
        case .year: return KeyPathComparator(\.year)
        case .genre: return KeyPathComparator(\.genre)
        case .bitrate: return KeyPathComparator(\.bitRate)
        case .rating: return KeyPathComparator(\.userRating)
        case .plays: return KeyPathComparator(\.playCount)
        case .added: return KeyPathComparator(\.created)
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

    /// Rows per render-window step (matches `PlaylistDetailView.pageSize`).
    private let pageSize = 300

    /// Render window size; first `displayedCount` rows of `songs` are shown.
    @State private var displayedCount: Int = 0
    private var displayedSongs: [SubsonicSong] { Array(songs.prefix(displayedCount)) }

    /// Tracks the selected rows so left-click selects and multi-select works.
    @State private var selection = Set<SubsonicSong.ID>()

    var body: some View {
        Table(displayedSongs, selection: $selection, sortOrder: $sortOrder,
              columnCustomization: $columnCustomization) {
            TableColumnForEach(SongColumn.allCases) { column in
                TableColumn(column.title, sortUsing: column.comparator) { song in
                    // Pass `app` explicitly: `Table` cells are hosted in an
                    // NSTableView that doesn't reliably propagate the SwiftUI
                    // environment, so `@Environment(AppState.self)` here would
                    // force-unwrap nil (crashes on sort, which re-lays-out rows).
                    SongColumnCell(column: column, song: song, app: app)
                        // Prefetch next page when the tail row appears. Only
                        // the title column installs the task — otherwise each
                        // row would create one task per column (×8–10).
                        .task {
                            guard column == .title else { return }
                            let lastIndex = min(displayedCount, songs.count) - 1
                            if lastIndex >= 0, song.id == songs[lastIndex].id, displayedCount < songs.count {
                                displayedCount = min(displayedCount + pageSize, songs.count)
                            }
                        }
                }
                .customizationID(column.id)
            }
        }
        .onAppear {
            // Start with a full page instead of an empty table until the
            // first scroll grows the window.
            displayedCount = min(pageSize, songs.count)
        }
        .onChange(of: songs.count) {
            displayedCount = min(displayedCount, songs.count)
        }
        .onChange(of: sortOrder) {
            // Reset to a single page on re-sort: `Table` re-sorts the handed-in
            // array synchronously, and if the window had grown to the whole
            // library that would re-materialize every row on the main thread —
            // the exact freeze we're avoiding. `SongsView` re-sorts the full
            // library off-main and lands a fresh page.
            displayedCount = min(pageSize, songs.count)
        }
        // Light-gray selection accent (matches the sidebar) instead of the red
        // accent, so a selected row reads as a neutral highlight, not a colored one.
        .tint(AMColor.sidebarSelection)
        // `contextMenu(forSelectionType:)` auto-selects the clicked row (and lets
        // Cmd/Shift multi-select), so the menu always has a concrete target.
        .contextMenu(forSelectionType: SubsonicSong.ID.self) { ids in
            if let id = ids.first, let song = songs.first(where: { $0.id == id }) {
                SongContextMenu(song: song, songs: songs, selection: selection, app: app)
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

    var body: some View {
        switch column {
        case .title:
            HStack(spacing: 6) {
                if app.player.currentSong?.id == song.id {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(AMColor.accent)
                }
                Text(song.displayTitle)
                    .fontWeight(app.player.currentSong?.id == song.id ? .semibold : .regular)
                    .lineLimit(1)
            }
        case .artist:
            Text(song.artist ?? "").foregroundStyle(.secondary)
        case .album:
            Text(song.album ?? "").foregroundStyle(.secondary)
        case .duration:
            if let duration = song.duration {
                Text(Player.format(seconds: Double(duration)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        case .year:
            Text(song.year.map(String.init) ?? "").foregroundStyle(.secondary)
        case .genre:
            Text(song.genre ?? "").foregroundStyle(.secondary)
        case .bitrate:
            Text(song.bitRate.map { "\($0) kbps" } ?? "")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        case .rating:
            RatingStars(song: song, app: app)
        case .plays:
            Text(song.playCount.map(String.init) ?? "")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        case .added:
             Text(SongTable.addedDateText(song.created))
                .foregroundStyle(.secondary)
        }
    }
}
