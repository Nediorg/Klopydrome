import SwiftUI
import NavidromeClient

/// Detail page for a specific genre, presenting all songs matching the genre
/// in a full tabular layout (`SongTable`) with play and shuffle controls.
struct GenreDetailView: View {
    @Environment(AppState.self) private var app

    let genreName: String

    @State private var loading = true
    @State private var songs: [SubsonicSong] = []
    @State private var loadError: String?

    @State private var sortOrder: [KeyPathComparator<SubsonicSong>] = [
        KeyPathComparator(\.title, order: .forward)
    ]
    @State private var columnCustomization: TableColumnCustomization<SubsonicSong> = {
        var customization = TableColumnCustomization<SubsonicSong>()
        for column in SongColumn.allCases {
            customization[visibility: column.id] = SongColumn.defaults.contains(column) ? .visible : .hidden
        }
        return customization
    }()

    private var sortedSongs: [SubsonicSong] {
        songs.sorted(using: sortOrder)
    }

    private var playableSongs: [SubsonicSong] {
        if app.isOfflineSession {
            return sortedSongs.filter { app.isCached($0) }
        }
        return sortedSongs
    }

    private var totalDuration: Int {
        songs.reduce(0) { $0 + ($1.duration ?? 0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            heroHeader
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 16)

            Divider()

            if loading && songs.isEmpty {
                ProgressView("Загрузка песен жанра…".localized)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError, songs.isEmpty {
                ContentUnavailableView {
                    Label("Не удалось загрузить треки".localized, systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Повторить".localized) {
                        Task { await loadGenreSongs() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if songs.isEmpty {
                ContentUnavailableView {
                    Label("Нет треков".localized, systemImage: "music.note")
                } description: {
                    Text("В этом жанре пока нет доступных песен.".localized)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                SongTable(
                    songs: sortedSongs,
                    sortOrder: $sortOrder,
                    columnCustomization: $columnCustomization
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: genreName) {
            await loadGenreSongs()
        }
    }

    private var heroHeader: some View {
        HStack(alignment: .top, spacing: 24) {
            Circle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 140, height: 140)
                .overlay(
                    Image(systemName: "microphone.dynamic.on.stand")
                        .font(.system(size: 54))
                        .foregroundStyle(.secondary)
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(genreName)
                    .font(.largeTitle.bold())
                    .lineLimit(2)

                Text("Жанр".localized)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)

                metaSection

                actionRow
                    .padding(.top, 10)
            }
            .padding(.top, 2)
            .animation(.easeInOut(duration: 0.2), value: loading)
        }
    }

    @ViewBuilder
    private var metaSection: some View {
        if !songs.isEmpty || loading {
            ZStack(alignment: .leading) {
                Text("0 песен · 0:00:00")
                    .font(.callout)
                    .hidden()

                if !songs.isEmpty {
                    metaRow
                } else if loading {
                    metaSkeleton
                }
            }
        }
    }

    private var metaSkeleton: some View {
        Capsule()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 130, height: 10)
            .shimmering()
            .clipShape(Capsule())
    }

    private var metaRow: some View {
        var parts: [String] = []
        parts.append("\(songs.count) \(Pluralized.song(songs.count))")
        if totalDuration > 0 {
            parts.append(Player.format(seconds: Double(totalDuration)))
        }
        return Text(parts.joined(separator: " · "))
            .font(.callout)
            .foregroundStyle(AMColor.secondaryText)
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            ActionPill(
                title: "Слушать",
                systemImage: "play.fill",
                filled: true
            ) {
                if !playableSongs.isEmpty {
                    app.play(playableSongs, at: 0)
                }
            }
            .disabled(playableSongs.isEmpty)

            ActionPill(
                title: "Перемешать",
                systemImage: "shuffle",
                filled: true
            ) {
                if !playableSongs.isEmpty {
                    app.playShuffled(playableSongs)
                }
            }
            .disabled(playableSongs.isEmpty)

            Spacer()

            RoundEllipsisMenu {
                genreContextMenuItems
            }
            .disabled(playableSongs.isEmpty)
            .help("Действия над жанром".localized)
        }
    }

    @ViewBuilder
    private var genreContextMenuItems: some View {
        Button("Слушать следующей".localized) {
            app.playNext(playableSongs)
        }
        Button("В конец очереди".localized) {
            app.playLater(playableSongs)
        }

        Divider()

        AddToPlaylistMenu(songs: playableSongs)

        if !app.isOfflineSession {
            let uncached = playableSongs.filter { !app.isCached($0) }
            Divider()
            Button("Загрузить".localized) {
                app.cacheGenre(name: genreName, songs: playableSongs)
            }
            .disabled(uncached.isEmpty)
        }
    }

    private func loadGenreSongs() async {
        if app.isOfflineSession || app.client == nil {
            songs = app.downloadedSongs.filter {
                $0.genre?.localizedCaseInsensitiveCompare(genreName) == .orderedSame
            }
            loading = false
            return
        }
        guard let client = app.client else { return }
        loading = true
        loadError = nil
        do {
            let fetched = try await client.getSongsByGenre(genre: genreName, count: 500)
            songs = fetched
        } catch {
            loadError = error.localizedDescription
        }
        loading = false
    }
}
