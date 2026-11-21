import SwiftUI
import NavidromeClient

struct MoreByArtist: View {
    let artistId: String
    let artistName: String
    var excludingAlbumID: String? = nil
    @Environment(AppState.self) private var app

    @State private var albums: [SubsonicAlbum] = []
    @State private var loaded = false

    var body: some View {
        if !albums.isEmpty || !loaded {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    app.openArtistInLibrary(Artist(id: artistId, name: artistName))
                } label: {
                    HStack(spacing: 6) {
                        Text(L10n.format("format.album.moreByArtist", artistName))
                            .font(.title2.bold())
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if !loaded {
                    ProgressView()
                        .padding(.vertical, 20)
                } else if !albums.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(albums) { album in
                                Button {
                                    app.openAlbumInLibrary(album)
                                } label: {
                                    AlbumCard(album: album)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.bottom, 4)
                    }
                    .scrollClipDisabled()
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .task(id: "\(artistId)|\(excludingAlbumID ?? "")|\(app.isOfflineSession)") { await load() }
        }
    }

    private func load() async {
        if app.isOfflineSession {
            albums = app.library.albums.filter {
                (($0.artistId != nil && $0.artistId == artistId) ||
                 ($0.artist != nil && $0.artist == artistName)) &&
                (excludingAlbumID == nil || $0.id != excludingAlbumID)
            }
            loaded = true
            return
        }
        guard let client = app.client else {
            loaded = true
            return
        }
        defer { loaded = true }
        let artist = try? await client.getArtist(id: artistId)
        let rawAlbums = artist?.album ?? []
        albums = rawAlbums.filter { excludingAlbumID == nil || $0.id != excludingAlbumID }
    }
}
