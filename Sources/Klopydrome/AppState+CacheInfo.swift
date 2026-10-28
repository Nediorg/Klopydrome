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
        cachedStreamKeys = Set(keys)
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
