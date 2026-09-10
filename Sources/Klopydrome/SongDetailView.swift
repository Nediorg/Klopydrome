import SwiftUI
import NavidromeClient

/// Single song detail (reached from a search jump/context). Shows artwork,
/// quick transport, offline download, and a full technical-metadata grid.
struct SongDetailView: View {
    let song: SubsonicSong
    @Environment(AppState.self) private var app

    private var isDownloading: Bool { app.downloadingSongIDs.contains(song.id) }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                CoverArtView(coverArt: song.coverArt, size: 200)
                VStack(spacing: 4) {
                    Text(song.displayTitle).font(.title.bold()).multilineTextAlignment(.center)
                    if let artistId = song.artistId, let artistName = song.artist {
                        NavigationLink(value: Artist(id: artistId, name: artistName)) {
                            Text(artistName).foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .hoverBrighten()
                    }
                    if let albumId = song.albumId, let albumName = song.album {
                        NavigationLink(value: SubsonicAlbum(id: albumId, album: albumName)) {
                            Text(albumName).foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .hoverBrighten()
                    }
                }
                HStack(spacing: 12) {
                    Button {
                        app.play([song], at: 0)
                    } label: {
                        Label("Слушать", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    if isDownloading {
                        ProgressView().controlSize(.small).frame(width: 24, height: 24)
                            .help("Загрузка…")
                    } else {
                        Button {
                            if app.isCached(song) {
                                Task { await app.removeFromCache(song) }
                            } else {
                                app.cacheSong(song)
                            }
                        } label: {
                            Label(app.isCached(song) ? "Загружено" : "Загрузить",
                                  systemImage: app.isCached(song) ? "checkmark.circle.fill" : "arrow.down.circle")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                metadataGrid
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var metadataGrid: some View {
        SongMetadataGrid(song: song)
            .frame(maxWidth: 620)
    }
}