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
    private var isPlayableOffline: Bool { !app.isOfflineSession || primaryCached }

    var body: some View {
        if let onPlay {
            Button("Слушать".localized) { onPlay() }
                .disabled(!isPlayableOffline)
        }
        Button("Слушать следующей".localized) { targets.forEach { app.playNext($0) } }
            .disabled(!isPlayableOffline)
        Button("В конец очереди".localized) { targets.forEach { app.playLater($0) } }
            .disabled(!isPlayableOffline)
        Divider()
        AddToPlaylistMenu(songs: targets)
        Button((app.isStarred(song) ? "Убрать из избранного" : "В избранное").localized) {
            targets.forEach { app.toggleStar($0) }
        }
        if primaryDownloading {
            Button("Загрузка…".localized) {}
                .disabled(true)
        } else {
            Button((primaryCached ? "Удалить загрузку" : "Загрузить").localized) {
                if primaryCached {
                    targets.forEach { song in Task { await app.removeFromCache(song) } }
                } else {
                    targets.forEach { app.cacheSong($0) }
                }
            }
            .disabled(app.isOfflineSession && !primaryCached)
        }
        Button("Скачать".localized) { app.downloadTrack(song) }
            .disabled(app.isOfflineSession && !primaryCached)
        Menu("Оценить".localized) {
            ForEach(1...5, id: \.self) { star in
                Button("\(star) \(Pluralized.star(star))") {
                    targets.forEach { app.setRating(star == app.effectiveRating(for: $0) ? 0 : star, for: $0) }
                }
            }
        }

        Divider()
        Button {
            app.playStation(from: song)
        } label: {
            Label("Создать станцию".localized, systemImage: "dot.radiowaves.left.and.right")
        }
        .disabled(app.isOfflineSession)

        if let albumId = song.albumId {
            Button {
                app.openAlbumInLibrary(.nowPlayingSummary(from: song, albumID: albumId))
            } label: {
                Label("Показать альбом в медиатеке".localized, systemImage: "square.stack")
            }
        }
        let collaborators = SongCollaborators.parse(from: song, library: app.library)
        if collaborators.count > 1 {
            Menu {
                ForEach(collaborators, id: \.name) { artist in
                    Button(artist.name) {
                        app.openArtistInLibrary(artist)
                    }
                }
            } label: {
                Label("Перейти к исполнителю".localized, systemImage: "music.mic")
            }
        } else if let singleArtist = collaborators.first {
            Button {
                app.openArtistInLibrary(singleArtist)
            } label: {
                Label("Перейти к исполнителю".localized, systemImage: "music.mic")
            }
        }

        Divider()
        Button {
            app.inspectSong(song)
        } label: {
            Label("Свойства…".localized, systemImage: "info.circle")
        }
        Button {
            let parts = [song.displayTitle, song.artist, song.album].compactMap { $0 }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(parts.joined(separator: " — "), forType: .string)
        } label: {
            Label("Скопировать".localized, systemImage: "doc.on.doc")
        }
        Button("Поделиться…".localized) {
            app.presentShare(ShareTarget(entityID: song.id, title: song.displayTitle, kind: .song))
        }
    }
}

/// Resolves all participating artists for a track (collaborators, features, album artists).
enum SongCollaborators {
    @MainActor
    static func parse(from song: SubsonicSong, library: LibraryCache) -> [Artist] {
        var resolved: [Artist] = []
        var seen = Set<String>()

        func appendArtist(_ artist: Artist) {
            let key = artist.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, !seen.contains(key) else { return }
            seen.insert(key)
            resolved.append(artist)
        }

        // 1. Structured OpenSubsonic artists
        if let artists = song.artists, !artists.isEmpty {
            for artist in artists {
                appendArtist(artist)
            }
        }

        // 2. Parse from song.artist string
        if let raw = song.artist, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var text = raw
            let delimiters = [" feat. ", " Feat. ", " ft. ", " Ft. ", " & ", ", ", " / ", " vs. ", " vs "]
            for delim in delimiters {
                text = text.replacingOccurrences(of: delim, with: "\u{1F}")
            }
            let names = text.components(separatedBy: "\u{1F}")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            for name in names {
                if let matched = library.findArtist(named: name) {
                    appendArtist(matched)
                } else if names.count == 1, let artistId = song.artistId {
                    appendArtist(Artist(id: artistId, name: name))
                } else {
                    appendArtist(Artist(id: name, name: name))
                }
            }
        }

        // 3. Fallback to song.artistId if nothing resolved
        if resolved.isEmpty, let artistId = song.artistId, let name = song.artist {
            appendArtist(Artist(id: artistId, name: name))
        }

        return resolved
    }
}
