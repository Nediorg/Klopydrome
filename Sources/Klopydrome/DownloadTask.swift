import Foundation
import SwiftUI
import NavidromeClient

/// A high-level download job representing a playlist, album, genre, or track batch.
struct DownloadTask: Identifiable, Equatable {
    enum Kind: Equatable {
        case album(album: SubsonicAlbum)
        case playlist(playlist: PlaylistSummary)
        case genre(name: String)
        case track(song: SubsonicSong)
        case batch(title: String)
    }

    let id: UUID
    let kind: Kind
    var coverArt: String?
    var songs: [SubsonicSong]
    var completedSongIDs: Set<String> = []
    var currentSongID: String?

    var totalCount: Int { songs.count }
    var completedCount: Int { completedSongIDs.count }

    var currentSong: SubsonicSong? {
        guard let currentSongID else { return nil }
        return songs.first(where: { $0.id == currentSongID })
    }

    var categoryTitle: String {
        switch kind {
        case .album: return "Альбом".localized
        case .playlist: return "Плейлист".localized
        case .genre: return "Жанр".localized
        case .track: return "Песня".localized
        case .batch: return "Песни".localized
        }
    }

    var title: String {
        switch kind {
        case .album(let album): return album.displayName
        case .playlist(let playlist): return playlist.displayName
        case .genre(let name): return name
        case .track(let song): return song.displayTitle
        case .batch(let title): return title
        }
    }

    var currentSongSubtitle: String {
        if let currentSong {
            if let artist = currentSong.artist, !artist.isEmpty {
                return "\(artist) — \(currentSong.displayTitle)"
            }
            return currentSong.displayTitle
        }
        return categoryTitle
    }

    var subtitle: String {
        switch kind {
        case .album, .playlist, .genre, .batch:
            if totalCount > 1 {
                return "\(categoryTitle) • \(completedCount)/\(totalCount)"
            } else {
                return categoryTitle
            }
        case .track(let song):
            if let artist = song.artist, !artist.isEmpty {
                return artist
            }
            return categoryTitle
        }
    }

    func progress(downloadProgress: [String: Double]) -> Double {
        guard totalCount > 0 else { return 1.0 }
        let currentFraction = currentSongID.flatMap { downloadProgress[$0] } ?? 0.0
        return min(1.0, (Double(completedCount) + currentFraction) / Double(totalCount))
    }
}

extension AppState {
    func startDownloadTask(
        kind: DownloadTask.Kind,
        coverArt: String?,
        songs: [SubsonicSong]
    ) {
        let targets = songs.filter { !isCached($0) }
        guard !targets.isEmpty else { return }

        let taskID = UUID()
        let task = DownloadTask(
            id: taskID,
            kind: kind,
            coverArt: coverArt,
            songs: targets,
            completedSongIDs: [],
            currentSongID: targets.first?.id
        )
        activeDownloadTasks.append(task)
        for song in targets {
            register(downloading: song)
        }
        if let firstID = targets.first?.id {
            downloadProgress[firstID] = 0.0
        }

        Task {
            for song in targets {
                if isDownloadCancelled(songID: song.id) {
                    continue
                }
                if isCached(song) {
                    await MainActor.run { markSongCompleted(in: taskID, songID: song.id) }
                    continue
                }
                await MainActor.run {
                    setCurrentSong(in: taskID, songID: song.id)
                    if downloadProgress[song.id] == nil {
                        downloadProgress[song.id] = 0.0
                    }
                }
                await downloadToCache(song)
                await MainActor.run { markSongCompleted(in: taskID, songID: song.id) }
            }
            await MainActor.run {
                unregisterDownload(from: targets)
                activeDownloadTasks.removeAll { $0.id == taskID }
            }
        }
    }

    func cancelDownloadTask(_ task: DownloadTask) {
        for song in task.songs {
            cancelDownload(song)
            downloadProgress.removeValue(forKey: song.id)
        }
        activeDownloadTasks.removeAll { $0.id == task.id }
        unregisterDownload(from: task.songs)
    }

    func markSongCompleted(in taskID: UUID, songID: String) {
        guard let index = activeDownloadTasks.firstIndex(where: { $0.id == taskID }) else { return }
        activeDownloadTasks[index].completedSongIDs.insert(songID)
        downloadProgress.removeValue(forKey: songID)
        if activeDownloadTasks[index].currentSongID == songID {
            let nextSong = activeDownloadTasks[index].songs.first { song in
                !activeDownloadTasks[index].completedSongIDs.contains(song.id)
            }
            activeDownloadTasks[index].currentSongID = nextSong?.id
            if let nextID = nextSong?.id {
                downloadProgress[nextID] = 0.0
            }
        }
    }

    func setCurrentSong(in taskID: UUID, songID: String?) {
        guard let index = activeDownloadTasks.firstIndex(where: { $0.id == taskID }) else { return }
        activeDownloadTasks[index].currentSongID = songID
    }

    func isDownloadCancelled(songID: String) -> Bool {
        cancelledDownloads.contains(songID)
    }

    func cancelDownloadSongInTask(taskID: UUID, song: SubsonicSong) {
        cancelDownload(song)
        downloadProgress.removeValue(forKey: song.id)
        if let index = activeDownloadTasks.firstIndex(where: { $0.id == taskID }) {
            activeDownloadTasks[index].songs.removeAll(where: { $0.id == song.id })
            if activeDownloadTasks[index].currentSongID == song.id {
                let nextSong = activeDownloadTasks[index].songs.first { candidate in
                    !activeDownloadTasks[index].completedSongIDs.contains(candidate.id)
                }
                activeDownloadTasks[index].currentSongID = nextSong?.id
                if let nextID = nextSong?.id {
                    downloadProgress[nextID] = 0.0
                }
            }
            if activeDownloadTasks[index].songs.isEmpty {
                activeDownloadTasks.remove(at: index)
            }
        }
    }

    func cacheSong(_ song: SubsonicSong) {
        guard !isCached(song) else { return }
        startDownloadTask(
            kind: .track(song: song),
            coverArt: song.coverArt,
            songs: [song]
        )
    }

    func cacheSongs(_ songs: [SubsonicSong], title: String? = nil) {
        let targets = songs.filter { !isCached($0) }
        guard !targets.isEmpty else { return }
        if targets.count == 1 {
            cacheSong(targets[0])
            return
        }
        startDownloadTask(
            kind: .batch(title: title ?? "Песни".localized),
            coverArt: targets.first?.coverArt,
            songs: targets
        )
    }

    func cacheAlbum(_ album: SubsonicAlbum) {
        guard let client else { return }
        Task {
            let songs = (try? await client.getAlbum(id: album.id))?.song ?? []
            guard !songs.isEmpty else { return }
            await MainActor.run {
                self.startDownloadTask(
                    kind: .album(album: album),
                    coverArt: album.coverArt ?? songs.first?.coverArt,
                    songs: songs
                )
            }
        }
    }

    func cacheCurrentAlbum() {
        guard let currentSong = player.currentSong, let albumId = currentSong.albumId else { return }
        guard let client else { return }
        Task {
            let songs = (try? await client.getAlbum(id: albumId))?.song ?? []
            guard !songs.isEmpty else { return }
            let album = self.library.albums.first(where: { $0.id == albumId })
                ?? SubsonicAlbum.nowPlayingSummary(from: currentSong, albumID: albumId)
            await MainActor.run {
                self.startDownloadTask(
                    kind: .album(album: album),
                    coverArt: currentSong.coverArt ?? songs.first?.coverArt,
                    songs: songs
                )
            }
        }
    }

    func cachePlaylist(_ playlist: PlaylistSummary) {
        Task {
            let songs = await playlistSongs(for: playlist)
            guard !songs.isEmpty else { return }
            await MainActor.run {
                self.startDownloadTask(
                    kind: .playlist(playlist: playlist),
                    coverArt: playlist.coverArt ?? songs.first?.coverArt,
                    songs: songs
                )
            }
        }
    }

    func cacheCurrentPlaylist() {
        guard let playlist = nav.selectedPlaylist else { return }
        cachePlaylist(playlist)
    }

    func cacheGenre(name: String, songs: [SubsonicSong]) {
        let targets = songs.filter { !isCached($0) }
        guard !targets.isEmpty else { return }
        startDownloadTask(
            kind: .genre(name: name),
            coverArt: targets.first?.coverArt,
            songs: targets
        )
    }
}
