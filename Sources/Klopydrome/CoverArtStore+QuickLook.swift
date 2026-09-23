import Foundation
import AppKit
import NavidromeClient

extension CoverArtStore {
    /// Synchronously retrieves any cached image for `coverArt` in memory,
    /// preferring the requested size, then larger, then any cached size (including thumbnail).
    func anyCachedImage(coverArt: String?, preferredDisplayPixels: Int? = nil) -> NSImage? {
        guard let coverArt, !coverArt.isEmpty else { return nil }
        if let preferredDisplayPixels,
           let exact = cachedImage(coverArt: coverArt, size: preferredDisplayPixels) {
            return exact
        }
        let sizes = lock.withLock { cachedSizes[coverArt] }
        guard let sizes, !sizes.isEmpty else { return nil }
        if sizes.contains(0), let img = memory.object(forKey: "\(coverArt)-orig" as NSString) {
            return img
        }
        for size in sizes.sorted(by: >) {
            let key = "\(coverArt)-\(size == 0 ? "orig" : String(size))"
            if let img = memory.object(forKey: key as NSString) {
                return img
            }
        }
        return nil
    }

    /// Dedicated directory inside system temp for exported cover files (e.g. Quick Look).
    /// Cleaned on startup to prevent disk bloat.
    static let tempCoversDirectory: URL = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("KlopydromeCovers", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for item in items {
                try? FileManager.default.removeItem(at: item)
            }
        }
        return dir
    }()

    /// Returns true if the full-resolution original cover is already cached on disk.
    func isFullCoverCached(coverArt: String?) async -> Bool {
        guard let coverArt, !coverArt.isEmpty else { return false }
        let fullTempURL = Self.tempCoversDirectory
            .appendingPathComponent("cover-\(coverArt).jpg")
        if FileManager.default.fileExists(atPath: fullTempURL.path),
           let size = (try? fullTempURL.resourceValues(forKeys: [.fileSizeKey]).fileSize), size > 0 {
            return true
        }
        guard let cache else { return false }
        let fullKey = CacheManager.coverKey(coverArt: coverArt, size: 0)
        return await cache.hasFile(for: .covers, key: fullKey)
    }

    /// Returns an immediately available local file URL for Quick Look preview.
    /// Checks full-res cover first, then cached thumbnail, then memory cache.
    /// Falls back to downloading full cover if not yet available.
    func quickLookFileURL(coverArt: String?, displayPixels: Int) async -> URL? {
        guard let coverArt, !coverArt.isEmpty else { return nil }

        // 1. If full-resolution cover was already copied to temp, return it.
        let fullTempURL = Self.tempCoversDirectory
            .appendingPathComponent("cover-\(coverArt).jpg")
        if FileManager.default.fileExists(atPath: fullTempURL.path),
           let size = (try? fullTempURL.resourceValues(forKeys: [.fileSizeKey]).fileSize), size > 0 {
            return fullTempURL
        }

        // 2. If full-resolution cover is cached on disk, copy to temp and return it.
        let fullKey = CacheManager.coverKey(coverArt: coverArt, size: 0)
        if let cache, await cache.hasFile(for: .covers, key: fullKey),
           let data = await cache.readData(for: .covers, key: fullKey) {
            try? data.write(to: fullTempURL, options: .atomic)
            return fullTempURL
        }

        // 3. If thumbnail was already copied to temp, return it.
        let thumbTempURL = Self.tempCoversDirectory
            .appendingPathComponent("cover-thumb-\(coverArt).jpg")
        if FileManager.default.fileExists(atPath: thumbTempURL.path),
           let size = (try? thumbTempURL.resourceValues(forKeys: [.fileSizeKey]).fileSize), size > 0 {
            return thumbTempURL
        }

        // 4. If thumbnail is cached on disk, copy to temp and return it.
        if let thumbURL = await cachedThumbnailFileURL(coverArt: coverArt, displayPixels: displayPixels) {
            return thumbURL
        }

        // 5. If we have any decoded NSImage in memory, write it to temp JPEG.
        if let image = anyCachedImage(coverArt: coverArt, preferredDisplayPixels: displayPixels),
           let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) {
            let memTempURL = Self.tempCoversDirectory
                .appendingPathComponent("cover-preview-\(coverArt).jpg")
            try? jpegData.write(to: memTempURL, options: .atomic)
            return memTempURL
        }

        // 6. Cold fallback: fetch original full-resolution cover from server.
        return await fullCoverFileURL(coverArt: coverArt)
    }

    /// File URL for the already-cached thumbnail (no network). Copied to a
    /// temp `.jpg` so Quick Look recognises it as image (cached file is `.img`).
    func cachedThumbnailFileURL(coverArt: String?, displayPixels: Int) async -> URL? {
        guard let coverArt, !coverArt.isEmpty, let cache else { return nil }
        let requested = coverResolution.requestedSize(forDisplayPixels: displayPixels)
        let cacheKey = CacheManager.coverKey(coverArt: coverArt, size: requested ?? 0)
        guard let data = await cache.readData(for: .covers, key: cacheKey) else { return nil }
        let tmp = Self.tempCoversDirectory
            .appendingPathComponent("cover-thumb-\(coverArt).jpg")
        try? data.write(to: tmp, options: .atomic)
        return tmp
    }

    /// File URL for the full-resolution cover, downloading it if needed. Copied
    /// to a temp `.jpg` so Quick Look recognises it as image.
    func fullCoverFileURL(coverArt: String?) async -> URL? {
        guard let coverArt, !coverArt.isEmpty else { return nil }
        let cacheKey = CacheManager.coverKey(coverArt: coverArt, size: 0)
        if let cache, !(await cache.hasFile(for: .covers, key: cacheKey)) {
            _ = await resolveCover(coverArt: coverArt, size: nil)
        }
        guard let cache, await cache.hasFile(for: .covers, key: cacheKey),
              let data = await cache.readData(for: .covers, key: cacheKey) else { return nil }
        let tmp = Self.tempCoversDirectory
            .appendingPathComponent("cover-\(coverArt).jpg")
        try? data.write(to: tmp, options: .atomic)
        return tmp
    }
}
