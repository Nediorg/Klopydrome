import Foundation
import SwiftUI
import NavidromeClient

struct DownloadTask: Identifiable, Equatable {
    enum Kind: Equatable {
        case album(album: SubsonicAlbum)
        case playlist(playlist: PlaylistSummary)
        case genre(name: String)
        case track(song: SubsonicSong)
        case batch(title: String)
    }

    enum State: Equatable {
        case queued
        case active
        case waitingForNetwork
        case completed
    }

    let id: UUID
    let kind: Kind
    var coverArt: String?
    var songs: [SubsonicSong]
    var completedSongIDs: Set<String> = []
    var failedSongIDs: Set<String> = []
    var currentSongID: String?
    var state: State = .queued

    var totalCount: Int { songs.count }
    var completedCount: Int { completedSongIDs.count }

    var currentSong: SubsonicSong? {
        guard let currentSongID else { return nil }
        return songs.first(where: { $0.id == currentSongID })
    }

    var categoryTitle: String {
        switch kind {
        case .album: return "Album".localized
        case .playlist: return "Playlist".localized
        case .genre: return "Genre".localized
        case .track: return "Song".localized
        case .batch: return "Songs".localized
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
        if state == .waitingForNetwork {
            return "Offline".localized
        }
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
        let isFirst = activeDownloadTasks.isEmpty
        let task = DownloadTask(
            id: taskID,
            kind: kind,
            coverArt: coverArt,
            songs: targets,
            completedSongIDs: [],
            failedSongIDs: [],
            currentSongID: targets.first?.id,
            state: isFirst ? .active : .queued
        )
        activeDownloadTasks.append(task)
        for song in targets {
            cancelledDownloads.remove(song.id)
            register(downloading: song)
        }
        if let firstID = targets.first?.id {
            if downloadProgress[firstID] == nil {
                downloadProgress[firstID] = 0.0
            }
        }
        processDownloadQueue()
    }

    func processDownloadQueue() {
        guard !isProcessingDownloadQueue else { return }
        guard let nextIndex = activeDownloadTasks.firstIndex(where: {
            $0.state == .queued || $0.state == .active || $0.state == .waitingForNetwork
        }) else {
            return
        }

        isProcessingDownloadQueue = true
        let taskID = activeDownloadTasks[nextIndex].id
        activeDownloadTasks[nextIndex].state = .active
        let workerID = UUID()
        activeDownloadWorkerID = workerID

        downloadWorkerTask = Task { [weak self] in
            await self?.runDownloadWorker(taskID: taskID, workerID: workerID)
        }
    }

    private func runDownloadWorker(taskID: UUID, workerID: UUID) async {
        defer {
            Task { @MainActor [weak self] in
                guard let self, self.activeDownloadWorkerID == workerID else { return }
                self.activeDownloadWorkerID = nil
                self.isProcessingDownloadQueue = false
                self.processDownloadQueue()
            }
        }

        guard let task = activeDownloadTasks.first(where: { $0.id == taskID }) else { return }
        let remainingSongs = task.songs.filter {
            !task.completedSongIDs.contains($0.id) && !task.failedSongIDs.contains($0.id)
        }

        for song in remainingSongs {
            if Task.isCancelled || isDownloadCancelled(songID: song.id) { break }
            if isCached(song) {
                await MainActor.run { markSongCompleted(in: taskID, songID: song.id) }
                continue
            }

            guard await waitForNetworkConnectivity(taskID: taskID, songID: song.id) else { return }

            await MainActor.run {
                setCurrentSong(in: taskID, songID: song.id)
                register(downloading: song)
                downloadProgress[song.id] = 0.0
            }

            let success = await executeSongDownloadWithRetry(song, in: taskID)
            if !success && !Task.isCancelled && !isDownloadCancelled(songID: song.id) {
                await MainActor.run { markSongFailed(in: taskID, songID: song.id) }
            }
        }

        await MainActor.run {
            activeDownloadTasks.removeAll { $0.id == taskID }
            unregisterDownload(from: task.songs)
        }
    }

    private func waitForNetworkConnectivity(taskID: UUID, songID: String) async -> Bool {
        while !NetworkMonitor.shared.isPathSatisfied {
            await MainActor.run { setTaskState(taskID, .waitingForNetwork) }
            if Task.isCancelled || isDownloadCancelled(songID: songID) { return false }
            try? await Task.sleep(for: .seconds(2))
        }
        await MainActor.run { setTaskState(taskID, .active) }
        return !Task.isCancelled && !isDownloadCancelled(songID: songID)
    }

    private func executeSongDownloadWithRetry(_ song: SubsonicSong, in taskID: UUID) async -> Bool {
        var attempt = 0
        while attempt < 3 && !Task.isCancelled {
            do {
                try await downloadToCache(song)
                await MainActor.run { markSongCompleted(in: taskID, songID: song.id) }
                return true
            } catch is CancellationError {
                return false
            } catch let error as URLError where isTransientNetworkError(error) {
                attempt += 1
                guard await waitForNetworkConnectivity(taskID: taskID, songID: song.id) else { return false }
                if attempt < 3 {
                    try? await Task.sleep(for: .milliseconds(500 * attempt))
                }
            } catch {
                return false
            }
        }
        return false
    }

    private func isTransientNetworkError(_ error: URLError) -> Bool {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut,
             .cannotConnectToHost, .dnsLookupFailed, .internationalRoamingOff,
             .callIsActive, .dataNotAllowed:
            return true
        default:
            return false
        }
    }

    func setTaskState(_ taskID: UUID, _ state: DownloadTask.State) {
        guard let index = activeDownloadTasks.firstIndex(where: { $0.id == taskID }) else { return }
        activeDownloadTasks[index].state = state
    }

    func cancelDownloadTask(_ task: DownloadTask) {
        let isCurrent = activeDownloadTasks.first?.id == task.id
        if isCurrent {
            activeDownloadWorkerID = nil
            downloadWorkerTask?.cancel()
            downloadWorkerTask = nil
        }
        for song in task.songs {
            cancelDownload(song)
            downloadProgress.removeValue(forKey: song.id)
        }
        activeDownloadTasks.removeAll { $0.id == task.id }
        unregisterDownload(from: task.songs)
        if isCurrent {
            isProcessingDownloadQueue = false
            processDownloadQueue()
        }
    }

    func markSongCompleted(in taskID: UUID, songID: String) {
        guard let index = activeDownloadTasks.firstIndex(where: { $0.id == taskID }) else { return }
        activeDownloadTasks[index].completedSongIDs.insert(songID)
        activeDownloadTasks[index].failedSongIDs.remove(songID)
        let stillInOtherTask = activeDownloadTasks.contains {
            $0.id != taskID && $0.songs.contains(where: { $0.id == songID })
        }
        if !stillInOtherTask {
            downloadingSongIDs.remove(songID)
            downloadingSongs.removeAll { $0.id == songID }
        }
        downloadProgress.removeValue(forKey: songID)
        if activeDownloadTasks[index].currentSongID == songID {
            let nextSong = activeDownloadTasks[index].songs.first { song in
                !activeDownloadTasks[index].completedSongIDs.contains(song.id) &&
                !activeDownloadTasks[index].failedSongIDs.contains(song.id)
            }
            activeDownloadTasks[index].currentSongID = nextSong?.id
            if let nextID = nextSong?.id {
                downloadProgress[nextID] = 0.0
            }
        }
    }

    func markSongFailed(in taskID: UUID, songID: String) {
        guard let index = activeDownloadTasks.firstIndex(where: { $0.id == taskID }) else { return }
        activeDownloadTasks[index].failedSongIDs.insert(songID)
        let stillInOtherTask = activeDownloadTasks.contains {
            $0.id != taskID && $0.songs.contains(where: { $0.id == songID })
        }
        if !stillInOtherTask {
            downloadingSongIDs.remove(songID)
            downloadingSongs.removeAll { $0.id == songID }
        }
        downloadProgress.removeValue(forKey: songID)
        if activeDownloadTasks[index].currentSongID == songID {
            let nextSong = activeDownloadTasks[index].songs.first { song in
                !activeDownloadTasks[index].completedSongIDs.contains(song.id) &&
                !activeDownloadTasks[index].failedSongIDs.contains(song.id)
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
                let isCurrent = activeDownloadTasks.first?.id == taskID
                if isCurrent {
                    activeDownloadWorkerID = nil
                    downloadWorkerTask?.cancel()
                    downloadWorkerTask = nil
                }
                activeDownloadTasks.remove(at: index)
                if isCurrent {
                    isProcessingDownloadQueue = false
                    processDownloadQueue()
                }
            }
        }
        let stillInOtherTask = activeDownloadTasks.contains { $0.songs.contains(where: { $0.id == song.id }) }
        if !stillInOtherTask {
            downloadingSongIDs.remove(song.id)
            downloadingSongs.removeAll { $0.id == song.id }
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
            kind: .batch(title: title ?? "Songs".localized),
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
