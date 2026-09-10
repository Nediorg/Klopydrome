import SwiftUI
import NavidromeClient

extension AppState {
    /// Fetches an album's tracks.
    func albumsSongs(_ album: SubsonicAlbum) async -> [SubsonicSong] {
        guard let client else { return [] }
        return (try? await client.getAlbum(id: album.id))?.song ?? []
    }

    /// Shuffles an album's tracks, loading them first.
    func playShuffled(_ album: SubsonicAlbum) async {
        let songs = await albumsSongs(album)
        guard !songs.isEmpty else { return }
        playShuffled(songs)
    }

    /// Queues an album's tracks at the end of the queue ("В конец очереди").
    func playLater(_ album: SubsonicAlbum) async {
        let songs = await albumsSongs(album)
        guard !songs.isEmpty else { return }
        guard !player.queue.isEmpty else {
            play(songs, at: 0)
            return
        }
        player.queue.append(contentsOf: songs)
    }

    /// Adds every track of an album to a playlist.
    func addAlbum(_ album: SubsonicAlbum, to playlistID: String) async {
        let songs = await albumsSongs(album)
        guard !songs.isEmpty else { return }
        await addToPlaylist(songs, playlistID: playlistID)
    }
}

/// Apple-Music-style context menu for an album. Single source of truth for
/// album actions — the album grid tiles, home shelves, artist-page cards and
/// the album-detail «…» button all build their menus from this component so
/// the offered actions can never drift apart.
///
/// Excluded (tied to iTunes/Apple-only or not applicable):
/// «Создать станцию», «Показать в iTunes Store», «Получить обложку»,
/// «Удалить из медиатеки».
struct AlbumContextMenuItems: View {
    @Environment(AppState.self) private var app
    let album: SubsonicAlbum

    private var isStarred: Bool { app.isStarred(album) }

    /// The album's tracks, fetched lazily once (used by the «Добавить в
    /// плейлист» submenu so it works from any surface without pre-loading).
    private var albumSongs: () async -> [SubsonicSong] {
        { await app.albumsSongs(album) }
    }

    var body: some View {
        Button(L10n.format("format.album.play", album.displayName)) {
            app.play(album)
        }
        Button(L10n.format("format.album.shuffle", album.displayName)) {
            Task { await app.playShuffled(album) }
        }
        Button("Слушать следующей") {
            app.playNext(album)
        }
        Button("В конец очереди") {
            Task { await app.playLater(album) }
        }

        Divider()
        AddToPlaylistMenu(songs: [], fetchSongs: albumSongs)
        Button(isStarred ? "Убрать из избранного" : "В избранное") {
            app.toggleStar(album)
        }
        Button("Загрузить альбом") {
            app.cacheAlbum(album)
        }

        Divider()
        Button("Поделиться…") {
            app.presentShare(ShareTarget(entityID: album.id, title: album.displayName, kind: .album))
        }
    }
}
