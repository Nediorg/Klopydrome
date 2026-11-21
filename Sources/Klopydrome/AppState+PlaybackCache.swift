import Foundation
import NavidromeClient

extension AppState {
    func candidateSuffixes(for song: SubsonicSong) -> [String] {
        var suffixes: [String] = []
        let download = downloadSuffix(for: song)
        if !download.isEmpty { suffixes.append(download) }
        let effective = effectiveSuffix(for: song)
        if !effective.isEmpty && !suffixes.contains(effective) { suffixes.append(effective) }
        if let raw = song.suffix?.lowercased(), !raw.isEmpty && !suffixes.contains(raw) {
            suffixes.append(raw)
        }
        for fallback in ["mp3", "flac", "m4a", "opus", "ogg", "aac", "wav"] where !suffixes.contains(fallback) {
            suffixes.append(fallback)
        }
        return suffixes
    }

    static func minimumExpectedCacheBytes(for song: SubsonicSong) -> Int {
        if let duration = song.duration, duration > 0 {
            return max(4096, Int(Double(duration) * 1500 * 0.75))
        }
        return 4096
    }

    func cachedURL(for song: SubsonicSong) -> URL? {
        guard let cache else { return nil }
        let minBytes = Self.minimumExpectedCacheBytes(for: song)
        for suffix in candidateSuffixes(for: song) {
            let key = CacheManager.streamKey(songId: song.id, suffix: suffix)
            let url = cache.fileURL(for: .streams, key: key)
            let exists = cachedStreamKeysSeeded
                ? cachedStreamKeys.contains(url.lastPathComponent)
                : FileManager.default.fileExists(atPath: url.path)
            guard exists else { continue }

            if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size >= minBytes {
                return url
            } else {
                try? FileManager.default.removeItem(at: url)
                cachedStreamKeys.remove(url.lastPathComponent)
            }
        }
        return nil
    }

    func handleLocalCacheFailure(for song: SubsonicSong) {
        guard let cache else { return }
        for suffix in candidateSuffixes(for: song) {
            let key = CacheManager.streamKey(songId: song.id, suffix: suffix)
            let url = cache.fileURL(for: .streams, key: key)
            try? FileManager.default.removeItem(at: url)
            cachedStreamKeys.remove(url.lastPathComponent)
        }
        downloadedSongs.removeAll { $0.id == song.id }
        Task { await removeOfflineSong(song) }
        if !isOfflineSession, let stream = streamURL(for: song) {
            let recordURL = beginAutomaticPlaybackCache(for: song, streamURL: stream)
            play(url: stream, streamRecordURL: recordURL)
        } else {
            player.handleEngineFailure("Unavailable".localized)
        }
    }

    func isCached(_ song: SubsonicSong) -> Bool {
        guard cache != nil else { return false }
        if !cachedStreamKeysSeeded { Task { await seedCachedStreamKeys() } }
        guard !cachedStreamKeys.isEmpty else { return false }
        let primaryKey = CacheManager.streamKey(songId: song.id, suffix: downloadSuffix(for: song))
        if let name = cacheFileName(for: primaryKey), cachedStreamKeys.contains(name) {
            return true
        }
        for suffix in candidateSuffixes(for: song) {
            let key = CacheManager.streamKey(songId: song.id, suffix: suffix)
            if let name = cacheFileName(for: key), cachedStreamKeys.contains(name) {
                return true
            }
        }
        return false
    }

    private func streamKey(for song: SubsonicSong) -> String {
        CacheManager.streamKey(songId: song.id, suffix: downloadSuffix(for: song))
    }

    private func cacheFileName(for key: String) -> String? {
        guard let cache else { return nil }
        return cache.fileURL(for: .streams, key: key).lastPathComponent
    }
}
