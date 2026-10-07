import SwiftUI
import NavidromeClient

/// Alphabetical genre index, mirroring the ArtistsView / Apple Music style.
struct GenresView: View {
    @Environment(AppState.self) private var app

    @State private var loading = true
    @State private var loadError: String?

    struct GenreIndex: Identifiable {
        var id: String { name }
        let name: String
        let genres: [Genre]
    }

    private var genres: [Genre] {
        if app.isOfflineSession {
            return app.offlineGenres(from: app.downloadedSongs)
        }
        return app.availableGenres
    }

    private var indexes: [GenreIndex] {
        let validGenres = genres.filter { !($0.value ?? "").isEmpty }
        let grouped = Dictionary(grouping: validGenres) { genre -> String in
            guard let first = (genre.value ?? "").first else { return "#" }
            let letter = String(first).uppercased()
            return letter.rangeOfCharacter(from: .letters) != nil ? letter : "#"
        }
        return grouped.map { letter, items in
            GenreIndex(
                name: letter,
                genres: items.sorted {
                    ($0.value ?? "").localizedCaseInsensitiveCompare($1.value ?? "") == .orderedAscending
                }
            )
        }
        .sorted {
            if $0.name == "#" { return false }
            if $1.name == "#" { return true }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        Group {
            if let loadError {
                LibraryUnavailableView(
                    title: "Не удалось загрузить",
                    systemImage: "wifi.exclamationmark",
                    message: loadError,
                    retry: { Task { await load() } }
                )
            } else if loading && indexes.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if indexes.isEmpty {
                LibraryUnavailableView(
                    title: "Нет жанров",
                    systemImage: "guitars",
                    message: "В вашей медиатеке пока нет размеченных жанров."
                )
            } else {
                List {
                    ForEach(indexes) { index in
                        Section(index.name) {
                            ForEach(index.genres) { genre in
                                let name = genre.value ?? "Неизвестный жанр".localized
                                Button {
                                    app.openGenre(name)
                                } label: {
                                    HStack(spacing: 12) {
                                        CircularGenreArt(name: name)
                                        Text(name)
                                        Spacer()
                                        if let count = genre.songCount, count > 0 {
                                            Text("\(count) \(Pluralized.song(count))")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        } else if let count = genre.albumCount, count > 0 {
                                            Text("\(count) \(Pluralized.album(count))")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
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
        guard app.availableGenres.isEmpty else {
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
            loading = false
            return
        }
        if app.availableGenres.isEmpty { loading = true }
        defer { loading = false }
        do {
            let genres = try await client.getGenres()
            app.availableGenres = genres
            loadError = nil
        } catch {
            if app.availableGenres.isEmpty {
                loadError = error.localizedDescription
            }
        }
    }
}

/// Circular thumbnail for a genre, matching CircularArtistArt.
struct CircularGenreArt: View {
    let name: String
    var size: CGFloat = 40

    var body: some View {
        let initial = name.first(where: { $0.isLetter || $0.isNumber }).map { String($0).uppercased() } ?? "?"
        ZStack {
            Circle().fill(Color.primary.opacity(0.08))
            Text(initial)
                .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
