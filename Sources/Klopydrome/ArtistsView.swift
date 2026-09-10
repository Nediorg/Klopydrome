import SwiftUI
import NavidromeClient

/// Alphabetical artist index, Apple Music style.
struct ArtistsView: View {
    @Environment(AppState.self) private var app

    private var indexes: [ArtistIndex] { app.library.artistIndexes }

    @State private var loading = true
    /// Set when the index fetch fails, so an error renders with retry instead
    /// of a misleading "Нет артистов".
    @State private var loadError: String?

    var body: some View {
        Group {
            if let loadError {
                LibraryUnavailableView(title: "Не удалось загрузить",
                                       systemImage: "wifi.exclamationmark",
                                       message: loadError,
                                       retry: { Task { await load() } })
            } else if loading && indexes.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if indexes.isEmpty {
                LibraryUnavailableView(title: "Нет артистов",
                                       systemImage: "music.mic",
                                       message: "В вашей библиотеке пока нет артистов.")
            } else {
                List {
                    ForEach(indexes, id: \.name) { index in
                        Section(index.name) {
                            ForEach(index.artist ?? []) { artist in
                                NavigationLink(value: artist) {
                                    HStack {
                                        CircularArtistArt(name: artist.name, imageURL: artist.artistImageUrl)
                                        Text(artist.name)
                                        Spacer()
                                        if let count = artist.albumCount {
                                            Text("\(count) \(Pluralized.album(count))")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
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
        .task { await loadIfNeeded() }
        .refreshable { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .foregroundRefreshRequested)) { _ in
            if loadError != nil {
                Task { await load() }
            }
        }
    }

    /// Fetches the artist index only when it has never been loaded, so a revisit
    /// to the tab is instant. Pull-to-refresh still forces a full reload.
    private func loadIfNeeded() async {
        guard !app.library.artistIndexesLoaded else { return }
        await load()
    }

    private func load() async {
        guard let client = app.client else { return }
        if app.library.artistIndexes.isEmpty { loading = true }
        defer { loading = false }
        do {
            let fresh = try await client.getArtists()
            loadError = nil
            app.library.artistIndexes = fresh
            app.library.artistIndexesLoaded = true
        } catch {
            if app.library.artistIndexes.isEmpty { loadError = error.localizedDescription }
        }
    }
}

struct CircularArtistArt: View {
    let name: String
    var imageURL: String? = nil
    var size: CGFloat = 40

    @State private var image: NSImage?
    /// Same foreground-retry nonce as cover tiles: re-fires the task below
    /// when failed artist images are invalidated store-wide.
    @State private var retryNonce = 0

    var body: some View {
        let initials = name.split(separator: " ").prefix(2).map(String.init).joined()
        ZStack {
            Circle().fill(Color.primary.opacity(0.1))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(initials)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .onReceive(NotificationCenter.default.publisher(for: .foregroundRefreshRequested)) { _ in
            retryNonce += 1
        }
        .task(id: CoverArtRequest(art: imageURL, nonce: retryNonce)) {
            let loaded = await CoverArtStore.shared.image(artistURL: imageURL, size: Int(size * 2))
            if let image = loaded.image {
                self.image = image
            }
        }
    }
}