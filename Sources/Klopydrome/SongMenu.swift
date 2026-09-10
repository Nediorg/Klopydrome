import SwiftUI
import NavidromeClient

/// One canonical set of per-song actions. This is the single source of truth
/// for "any song, anywhere" — the Songs-table selection menu, every `SongRow`
/// right-click and hover ellipsis, and the playback-bar «…» menu for the
/// current track all build from these items so the actions never drift apart.
///
/// The component takes an explicit `AppState` (not `@Environment`) because the
/// Songs table hosts these menus inside an NSTableView where the SwiftUI
/// environment is not reliably resolved.
struct SongActionItems: View {
    let app: AppState
    /// The song whose state drives the labels (starred / downloaded / rating).
    let song: SubsonicSong
    /// Songs the actions apply to (e.g. a table multi-selection). Defaults to
    /// just `song`.
    var selection: [SubsonicSong] = []
    /// When set, adds «Слушать» on top. Let the host choose: rows with a
    /// double-click already play, and the now-playing song is already playing.
    var onPlay: (() -> Void)?

    private var targets: [SubsonicSong] { selection.isEmpty ? [song] : selection }
    private var primaryCached: Bool { app.isCached(song) }
    private var primaryDownloading: Bool { app.downloadingSongIDs.contains(song.id) }

    var body: some View {
        if let onPlay {
            Button("Слушать") { onPlay() }
        }
        Button("Слушать следующей") { targets.forEach { app.playNext($0) } }
        Button("В конец очереди") { targets.forEach { app.playLater($0) } }
        Divider()
        AddToPlaylistMenu(songs: targets)
        Button(app.isStarred(song) ? "Убрать из избранного" : "В избранное") {
            targets.forEach { app.toggleStar($0) }
        }
        if primaryDownloading {
            Button("Загрузка…") {}
                .disabled(true)
        } else {
            Button(primaryCached ? "Удалить загрузку" : "Загрузить") {
                if primaryCached {
                    targets.forEach { song in Task { await app.removeFromCache(song) } }
                } else {
                    targets.forEach { app.cacheSong($0) }
                }
            }
        }
        Button("Скачать") { app.downloadTrack(song) }
        Menu("Оценить") {
            ForEach(1...5, id: \.self) { star in
                Button("\(star) \(Pluralized.star(star))") {
                    targets.forEach { app.setRating(star == app.effectiveRating(for: $0) ? 0 : star, for: $0) }
                }
            }
        }

        Divider()
        Button("Поделиться…") {
            app.presentShare(ShareTarget(entityID: song.id, title: song.displayTitle, kind: .song))
        }
    }
}

/// Left-click menu for a song's title/subtitle — “go to” navigation.
/// Shown as a `Menu` on the title row so a single click reveals the
/// destination picker instead of navigating immediately.
struct GoToSongMenuItems: View {
    let app: AppState
    let song: SubsonicSong

    var body: some View {
        if let artistId = song.artistId, !(song.artist?.isEmpty ?? true) {
            Button {
                app.openArtistInLibrary(.nowPlayingSummary(from: song, artistID: artistId))
            } label: {
                Label("Перейти к исполнителю", systemImage: "music.mic")
            }
        }
        if let albumId = song.albumId {
            Button {
                app.openAlbumInLibrary(.nowPlayingSummary(from: song, albumID: albumId))
            } label: {
                Label("Перейти к альбому", systemImage: "square.stack")
            }
        }
        let containing = app.playlistsContaining(song)
        if !containing.isEmpty {
            if containing.count == 1, let playlist = containing.first {
                Button {
                    app.openPlaylist(playlist)
                } label: {
                    Label("Перейти к плейлисту", systemImage: "music.note.list")
                }
            } else {
                Menu {
                    ForEach(containing) { playlist in
                        Button(playlist.displayName) {
                            app.openPlaylist(playlist)
                        }
                    }
                } label: {
                    Label("Перейти к плейлисту", systemImage: "music.note.list")
                }
            }
        }
    }
}
