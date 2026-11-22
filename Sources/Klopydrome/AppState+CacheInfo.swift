import Foundation
import NavidromeClient

extension AppState {

    func applyCacheLimits() async {
        guard let cache else { return }
        var limits = await cache.limits
        var stream = serverConfig.streamCacheLimitBytes ?? limits.maxStreamsBytes
        if let total = serverConfig.totalCacheLimitBytes, stream > total { stream = total }
        limits.maxStreamsBytes = stream
        if let value = serverConfig.totalCacheLimitBytes { limits.maxTotalBytes = value }
        await cache.setLimits(limits)
    }

    func seedCachedStreamKeys() async {
        guard !cachedStreamKeysSeeded else { return }
        cachedStreamKeysSeeded = true
        guard let cache else { return }
        let keys = await cache.fileKeys(for: .streams)
        let dir = cache.directory(for: .streams)
        var validKeys: [String] = []
        validKeys.reserveCapacity(keys.count)
        for key in keys {
            let url = dir.appendingPathComponent(key)
            if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size >= 4096 {
                validKeys.append(key)
            } else {
                try? FileManager.default.removeItem(at: url)
            }
        }
        cachedStreamKeys = Set(validKeys)
        pruneStaleRecordings(in: cache)
    }

    private func pruneStaleRecordings(in cache: CacheManager) {
        let recDir = cache.directory(for: .streams)
            .deletingLastPathComponent()
            .appendingPathComponent("recording", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(at: recDir, includingPropertiesForKeys: nil) else { return }
        let activeURL = automaticPlaybackRecording?.temporaryURL
        for file in files where file != activeURL {
            try? FileManager.default.removeItem(at: file)
        }
    }

    func resetCacheState() {
        cachedStreamKeys = []
        cachedStreamKeysSeeded = false
    }

    func clearCache() async {
        cancelAutomaticPlaybackCache()
        cachedStreamKeys = []
        cachedStreamKeysSeeded = true
        replaceDownloadedSongs([])
        await clearOfflineCatalog()
        CoverArtStore.shared.clearMemoryCache()
        clearInMemoryCaches()
        await smartPlaylistEngine?.clearCache()
        guard let cache else { return }
        await cache.clear()
    }

    func cacheSizeDescription() async -> String {
        guard let cache else { return "0 KB" }
        let bytes = await cache.totalBytesAsync()
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    func cacheSizeDescription(for kind: CacheKind) async -> String {
        guard let cache else { return "0 KB" }
        let bytes = await cache.bytesAsync(for: kind)
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
