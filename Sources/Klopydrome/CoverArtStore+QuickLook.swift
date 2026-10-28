import Foundation
import AppKit
import NavidromeClient

extension CoverArtStore {
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

    static let quickLookCandidateSizes = [1000, 720, 1200, 2048, 0, 750, 500, 360, 240, 200, 160, 80]

    func cachedQuickLookFileURL(coverArt: String?, displayPixels: Int = 1000) -> URL? {
        guard let coverArt, !coverArt.isEmpty, let cache else { return nil }

        let targetURL = Self.tempCoversDirectory.appendingPathComponent("cover-\(coverArt).jpg")
        if let values = try? targetURL.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey]) {
            if values.isSymbolicLink == true {
                try? FileManager.default.removeItem(at: targetURL)
            } else if let size = values.fileSize, size > 0 {
                return targetURL
            }
        }

        for candidate in Self.quickLookCandidateSizes {
            let key = CacheManager.coverKey(coverArt: coverArt, size: candidate)
            let sourceURL = cache.fileURL(for: .covers, key: key)
            if FileManager.default.fileExists(atPath: sourceURL.path),
               let size = (try? sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize), size > 0 {
                if copyToTemp(from: sourceURL, to: targetURL) {
                    return targetURL
                }
            }
        }

        if let image = anyCachedImage(coverArt: coverArt, preferredDisplayPixels: displayPixels),
           let jpegData = Self.encodeJPEG(image: image) {
            try? jpegData.write(to: targetURL, options: .atomic)
            return targetURL
        }

        return nil
    }

    func isFullCoverCached(coverArt: String?) async -> Bool {
        guard let coverArt, !coverArt.isEmpty, let cache else { return false }
        let fullKey = CacheManager.coverKey(coverArt: coverArt, size: 0)
        return await cache.hasFile(for: .covers, key: fullKey)
    }

    func quickLookFileURL(coverArt: String?, displayPixels: Int) async -> URL? {
        guard let coverArt, !coverArt.isEmpty else { return nil }

        if let cached = cachedQuickLookFileURL(coverArt: coverArt, displayPixels: displayPixels) {
            return cached
        }

        return await optimizedCoverFileURL(coverArt: coverArt, displayPixels: displayPixels)
    }

    func cachedThumbnailFileURL(coverArt: String?, displayPixels: Int) async -> URL? {
        cachedQuickLookFileURL(coverArt: coverArt, displayPixels: displayPixels)
    }

    func fullCoverFileURL(coverArt: String?) async -> URL? {
        guard let coverArt, !coverArt.isEmpty, let cache else { return nil }
        let fullKey = CacheManager.coverKey(coverArt: coverArt, size: 0)
        let sourceURL = cache.fileURL(for: .covers, key: fullKey)
        let targetURL = Self.tempCoversDirectory.appendingPathComponent("cover-\(coverArt)-full.jpg")

        if FileManager.default.fileExists(atPath: sourceURL.path),
           let size = (try? sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize), size > 0 {
            if copyToTemp(from: sourceURL, to: targetURL) {
                return targetURL
            }
        }

        let outcome = await resolveCover(coverArt: coverArt, size: nil)
        if case .image = outcome,
           FileManager.default.fileExists(atPath: sourceURL.path) {
            if copyToTemp(from: sourceURL, to: targetURL) {
                return targetURL
            }
        }

        return nil
    }

    private func optimizedCoverFileURL(coverArt: String, displayPixels: Int) async -> URL? {
        let targetSize = max(displayPixels, 1000)
        _ = await resolveCover(coverArt: coverArt, size: targetSize)

        return cachedQuickLookFileURL(coverArt: coverArt, displayPixels: displayPixels)
    }

    private func copyToTemp(from sourceURL: URL, to targetURL: URL) -> Bool {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: targetURL.path) {
            try? fileManager.removeItem(at: targetURL)
        }
        do {
            try fileManager.copyItem(at: sourceURL, to: targetURL)
            return true
        } catch {
            return false
        }
    }

    static func encodeJPEG(image: NSImage) -> Data? {
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let rep = NSBitmapImageRep(cgImage: cgImage)
            return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
        }
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
    }
}
