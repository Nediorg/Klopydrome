import SwiftUI
import NavidromeClient

struct AlbumContextMenuItems: View {
    @Environment(AppState.self) private var app
    let album: SubsonicAlbum

    private var isStarred: Bool { app.isStarred(album) }

    private var albumSongs: () async -> [SubsonicSong] {
        { await app.albumSongs(album) }
    }

    var body: some View {
        Button(L10n.format("format.album.play", album.displayName)) {
            app.play(album)
        }
        Button(L10n.format("format.album.shuffle", album.displayName)) {
            Task { await app.playShuffled(album) }
        }
        Button("Play Next".localized) {
            Task { await app.playNext(album) }
        }
        Button("Play Later".localized) {
            Task { await app.playLater(album) }
        }

        Divider()
        AddToPlaylistMenu(songs: [], fetchSongs: albumSongs)
        Button((isStarred ? "Unstar" : "Star").localized) {
            app.toggleStar(album)
        }
        if app.isAlbumDownloading(album.id) {
            Button("Cancel Download".localized) {
                app.cancelAlbumDownload(album.id)
            }
        } else {
            Button("Download Album".localized) {
                app.cacheAlbum(album)
            }
            .disabled(app.isOfflineSession)
        }

        Divider()
        Button("Share…".localized) {
            app.presentShare(ShareTarget(entityID: album.id, title: album.displayName, kind: .album))
        }
    }
}
