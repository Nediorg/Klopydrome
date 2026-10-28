import SwiftUI
import NavidromeClient

struct ArtistsView: View {
    @Environment(AppState.self) private var app

    private var indexes: [ArtistIndex] {
        if app.isOfflineSession {
            return app.offlineArtistIndexes(from: app.downloadedSongs)
        }
        return app.library.artistIndexes
    }

    @State private var loading = true
    @State private var loadError: String?

    var body: some View {
        Group {
            if let loadError {
                LibraryUnavailableView(title: "Failed to load".localized,
                                       systemImage: "wifi.exclamationmark",
                                       message: loadError,
                                       retry: { Task { await load() } })
            } else if loading && indexes.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if indexes.isEmpty {
                LibraryUnavailableView(title: "No Artists".localized,
                                       systemImage: "music.mic",
                                       message: "There are no artists in your library yet.".localized)
            } else {
                List {
                    ForEach(indexes, id: \.name) { index in
                        Section(index.name) {
                            ForEach(index.artist ?? []) { artist in
                                Button {
                                    app.openArtistInLibrary(artist)
                                } label: {
                                    HStack {
                                        CircularArtistArt(
                                            name: artist.name,
                                            imageURL: artist.artistImageUrl,
                                            coverArt: artist.coverArt ?? app.coverArtForArtist(artist)
                                        )
                                        Text(artist.name)
                                            .font(AMFont.rowTitle)
                                            .foregroundStyle(AMColor.primaryText)
                                        Spacer()
                                        if let count = artist.albumCount {
                                            Text("\(count) \(Pluralized.album(count))")
                                                .font(AMFont.rowSubtitle)
                                                .foregroundStyle(AMColor.secondaryText)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    ArtistContextMenuItems(artist: artist)
                                }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: "\(app.isConnected)|\(app.isOfflineSession)|\(app.nav.navVersion)") {
            await loadIfNeeded()
        }
        .refreshable {
            if app.isOfflineSession {
                _ = await app.reconnect()
            } else {
                await load()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .foregroundRefreshRequested)) { _ in
            if loadError != nil {
                Task { await load() }
            }
        }
    }

    private func loadIfNeeded() async {
        if app.isOfflineSession {
            loading = false
            return
        }
        guard app.client != nil else { return }
        guard !app.library.artistIndexesLoaded || indexes.isEmpty else {
            loading = false
            return
        }
        await load()
    }

    private func load() async {
        if app.isOfflineSession {
            loading = false
            return
        }
        guard let client = app.client else {
            return
        }
        if app.library.artistIndexes.isEmpty { loading = true }
        defer { loading = false }
        do {
            let fresh = try await client.getArtists()
            loadError = nil
            app.library.artistIndexes = fresh
            app.library.artistIndexesLoaded = true
            await app.persistArtistsToDisk()
        } catch {
            if app.library.artistIndexes.isEmpty {
                loadError = error.localizedDescription
            }
        }
    }
}

struct CircularArtistArt: View {
    let name: String
    var imageURL: String?
    var coverArt: String?
    var size: CGFloat

    init(name: String, imageURL: String? = nil, coverArt: String? = nil, size: CGFloat = 40) {
        self.name = name
        self.imageURL = imageURL
        self.coverArt = coverArt
        self.size = size
    }

    @State private var image: NSImage?
    @State private var retryNonce = 0

    private var displayImage: NSImage? {
        image ?? CoverArtStore.shared.cachedArtistImage(artistURL: imageURL, size: Int(size * 2))
    }

    var body: some View {
        let initial = name.first(where: { $0.isLetter || $0.isNumber }).map { String($0).uppercased() } ?? "?"
        ZStack {
            Circle().fill(Color.primary.opacity(0.1))
            if let img = displayImage {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else if let cover = coverArt, !cover.isEmpty {
                CoverArtView(coverArt: cover, size: size, cornerRadius: size / 2)
            } else {
                Text(initial)
                    .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .onReceive(NotificationCenter.default.publisher(for: .foregroundRefreshRequested)) { _ in
            retryNonce += 1
        }
        .task(id: CoverArtRequest(art: imageURL, nonce: retryNonce)) {
            if displayImage != nil { return }
            let loaded = await CoverArtStore.shared.image(artistURL: imageURL, size: Int(size * 2))
            guard !Task.isCancelled else { return }
            if let image = loaded.image {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        self.image = image
                    }
                }
            }
        }
    }
}

struct ArtistTile: View {
    @Environment(AppState.self) private var app
    let artist: Artist
    var size: CGFloat = 80
    var coverArt: String?

    var body: some View {
        Button {
            app.openArtistInLibrary(artist)
        } label: {
            VStack(spacing: 6) {
                CircularArtistArt(
                    name: artist.name,
                    imageURL: artist.artistImageUrl,
                    coverArt: coverArt ?? artist.coverArt ?? app.coverArtForArtist(artist),
                    size: size
                )
                Text(artist.name)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: size, alignment: .top)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            ArtistContextMenuItems(artist: artist)
        }
    }
}