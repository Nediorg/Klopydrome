import Foundation
import NavidromeClient

extension AppState {
    // MARK: Cache info

    /// Applies the persisted stream/total cache ceilings to the active cache
    /// manager, falling back to the platform defaults when unset.
    func applyCacheLimits() async {
        guard let cache else { return }
        var limits = await cache.limits
        // Audio streams are a subset of the total store, so the streams cap can
        // never exceed the overall cap — otherwise the global eviction would
        // fight the per-stream ceiling and the UI would show contradictory
        // limits. Clamp here (defensively) too, not just in the settings UI.
        var stream = serverConfig.streamCacheLimitBytes ?? limits.maxStreamsBytes
        if let total = serverConfig.totalCacheLimitBytes, stream > total { stream = total }
        limits.maxStreamsBytes = stream
        if let value = serverConfig.totalCacheLimitBytes { limits.maxTotalBytes = value }
        await cache.setLimits(limits)
    }

    /// Fills `cachedStreamKeys` from disk once per connection, so `isCached(_:)`
    /// can stay O(1) afterwards. Seeded on connect via a background task (and
    /// lazily if a menu builds before that finishes), so the directory listing
    /// of the streams store never blocks the main actor.
    func seedCachedStreamKeys() async {
        guard !cachedStreamKeysSeeded else { return }
        cachedStreamKeysSeeded = true
        guard let cache else { return }
        let keys = await cache.fileKeys(for: .streams)
        cachedStreamKeys = Set(keys)
    }

    /// Drops the in-memory cache-state snapshot when the cache manager changes
    /// server (or is torn down), forcing a fresh seed from the new store.
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
