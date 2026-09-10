import SwiftUI
import NavidromeClient

struct SearchResultsView: View {
    let query: String
    @Environment(AppState.self) private var app

    @State private var artists: [Artist] = []
    @State private var albums: [SubsonicAlbum] = []
    @State private var songs: [SubsonicSong] = []
    @State private var loading = true

    var body: some View {
        VStack(spacing: 0) {
            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if query.isEmpty {
                // The field is empty — no search has actually been performed
                // (it was cleared after a previous submit). A neutral prompt
                // beats a misleading "Ничего не найдено", which belongs to a
                // real query that matched nothing.
                ContentUnavailableView("Ищите музыку",
                                       systemImage: "magnifyingglass",
                                       // swiftlint:disable:next line_length
                                        description: Text("Введите запрос, чтобы найти исполнителей, альбомы и песни.".localized))
                    .emptyStatePinnedToTop()
            } else if isAllEmpty {
                ContentUnavailableView("Ничего не найдено",
                                        systemImage: "magnifyingglass",
                                       // swiftlint:disable:next line_length
                                        description: Text("Попробуйте изменить запрос или параметры фильтра.".localized))
                    .emptyStatePinnedToTop()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        if !artists.isEmpty { artistSection }
                        if !albums.isEmpty { albumSection }
                        if !songs.isEmpty { songSection }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                }
                .scrollClipDisabled()
            }
        }
        // Restart on a new query (live typing) AND on a repeated submit of the
        // same query: `submitSearch` bumps `navVersion`, which is part of the
        // task id here — a plain `.task(id: query)` would ignore the second
        // request when the query text is unchanged.
        .task(id: "\(app.nav.navVersion)|\(query)") { await load() }
    }

    private var isAllEmpty: Bool { artists.isEmpty && albums.isEmpty && songs.isEmpty }

    private var artistSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Исполнители".localized).font(.title3.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(artists) { artist in
                        NavigationLink(value: artist) {
                            VStack(spacing: 6) {
                                CircularArtistArt(name: artist.name, imageURL: artist.artistImageUrl, size: 80)
                                Text(artist.name)
                                    .font(.caption)
                                    .lineLimit(2)
                                    .frame(width: 80)
                            }
                            .contentShape(Rectangle())
                            .hoverScale(1.05)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
            }
            .scrollClipDisabled()
        }
    }

    private var albumSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Альбомы".localized).font(.title3.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(albums) { album in
                        NavigationLink(value: album) {
                            AlbumCard(album: album)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
            }
            .scrollClipDisabled()
        }
    }

    private var songSection: some View {
        let currentID = app.player.currentSong?.id
        return VStack(alignment: .leading, spacing: 8) {
            Text("Песни".localized).font(.title3.bold())
            LazyVStack(spacing: 0) {
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    SongRow(song: song, index: index, showAlbum: true,
                            isCurrentOverride: currentID == song.id,
                            onPlay: { idx in app.play(songs, at: idx) })
                    if index < songs.count - 1 { Divider().opacity(0.3) }
                }
            }
        }
    }

    private func load() async {
        loading = true
        defer {
            if !Task.isCancelled { loading = false }
        }
        // Debounce: `query` may change on every keystroke; pause a beat so only
        // the final value issues a request. If the query changed meanwhile, the
        // `.task(id:)` cancels this task before it fires.
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        guard let client = app.client, !query.isEmpty else { return }
        let result = try? await client.search3(query: query)
        // URLSession cancellation may race with a completed response. Do not
        // let an older search task overwrite the newer query's results.
        guard !Task.isCancelled else { return }
        artists = result?.artists ?? []
        albums = result?.albums ?? []
        songs = result?.songs ?? []
    }
}