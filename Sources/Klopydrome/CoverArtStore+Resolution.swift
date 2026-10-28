import Foundation
import NavidromeClient
import AppKit
import CoreGraphics
import ImageIO
import os

extension CoverArtStore {
    func resolveCover(coverArt: String, size: Int?) async -> FetchOutcome {
        let cacheKey = CacheManager.coverKey(coverArt: coverArt, size: size ?? 0)
        if let cache, let data = await cache.readData(for: .covers, key: cacheKey),
           let image = decodeImage(from: data, requestedSize: size) {
            // swiftlint:disable:next line_length
            coverLogger.debug("disk hit coverArt=\(coverArt, privacy: .private) size=\(size.map(String.init) ?? "orig", privacy: .private)")
            return .image(image)
        }
        // Disk fallback: if exact size is missing on disk, inspect larger cached sizes
        // (e.g. 720, 1200, 0/orig) and downsample in memory without network or disk duplication.
        if let size, size > 0, let larger = await findLargerCachedCoverOnDisk(coverArt: coverArt, than: size) {
            return .image(larger)
        }
        guard let client else {
            // Offline fallback: check any available cached size on disk (smaller or alternative bucket)
            // so offline mode renders actual artwork instead of a placeholder.
            if let fallback = await findAnyCachedCoverOnDisk(coverArt: coverArt, requestedSize: size) {
                return .image(fallback)
            }
            return .transient
        }
        guard let url = client.coverArtURL(id: coverArt, size: size) else {
            // swiftlint:disable:next line_length
            coverLogger.error("no url for coverArt=\(coverArt, privacy: .private) size=\(size.map(String.init) ?? "orig", privacy: .private)")
            return .dead
        }
        coverLogger.debug("fetch coverArt=\(coverArt, privacy: .private) url=\(url.absoluteString, privacy: .private)")
        let outcome = await fetch(url: url, cacheKey: cacheKey, requestedSize: size)
        if case .image = outcome, let cache, size == nil || (size ?? 0) >= 720 {
            // A high-resolution copy is now on disk; any obsolete low-res thumbnail file can be evicted.
            let thumbKey = CacheManager.coverKey(coverArt: coverArt, size: 240)
            if thumbKey != cacheKey {
                await cache.removeFile(for: .covers, key: thumbKey)
            }
        }
        if case .transient = outcome,
           let fallback = await findAnyCachedCoverOnDisk(coverArt: coverArt, requestedSize: size) {
            return .image(fallback)
        }
        return outcome
    }

    private static let candidateFallbackSizes = [0, 2048, 1200, 1000, 750, 720, 500, 360, 240, 200, 160, 80]

    /// Searches disk for any available cached version of `coverArt` when exact and
    /// strictly larger sizes are missing (crucial for offline sessions or network drops).
    /// Orders candidates from highest available down to lowest.
    func findAnyCachedCoverOnDisk(coverArt: String, requestedSize: Int?) async -> NSImage? {
        guard let cache else { return nil }
        let candidates: [Int]
        if let requested = requestedSize, requested > 0 {
            let larger = Self.candidateFallbackSizes.filter { $0 > requested }.sorted()
            let smaller = Self.candidateFallbackSizes.filter { $0 > 0 && $0 < requested }.sorted(by: >)
            candidates = larger + (Self.candidateFallbackSizes.contains(0) ? [0] : []) + smaller
        } else {
            candidates = Self.candidateFallbackSizes.filter { $0 > 0 }.sorted(by: >)
        }

        for candidate in candidates {
            let key = CacheManager.coverKey(coverArt: coverArt, size: candidate)
            if await cache.hasFile(for: .covers, key: key),
               let data = await cache.readData(for: .covers, key: key),
               let image = decodeImage(from: data, requestedSize: requestedSize) {
                // swiftlint:disable:next line_length
                coverLogger.debug("disk reuse fallback coverArt=\(coverArt, privacy: .private) found=\(candidate) for=\(requestedSize.map(String.init) ?? "orig")")
                lock.withLock {
                    _ = cachedSizes[coverArt, default: []].insert(requestedSize ?? 0)
                }
                return image
            }
        }
        return nil
    }

    /// Looks for a larger version of `coverArt` already stored on disk.
    /// If found, downsamples it in memory, registers it in `cachedSizes`,
    /// and returns the bounded image without writing duplicate files to disk.
    private func findLargerCachedCoverOnDisk(coverArt: String, than size: Int) async -> NSImage? {
        guard let cache else { return nil }
        for largerSize in CoverResolution.candidateLargerSizes(than: size) {
            let largerKey = CacheManager.coverKey(coverArt: coverArt, size: largerSize)
            if await cache.hasFile(for: .covers, key: largerKey),
               let data = await cache.readData(for: .covers, key: largerKey),
               let image = decodeImage(from: data, requestedSize: size) {
                // swiftlint:disable:next line_length
                coverLogger.debug("disk reuse larger coverArt=\(coverArt, privacy: .private) found=\(largerSize) for=\(size)")
                lock.withLock {
                    _ = cachedSizes[coverArt, default: []].insert(size)
                }
                return image
            }
        }
        return nil
    }

    func resolveArtist(artistURL: String, size: Int) async -> FetchOutcome {
        let resolved: URL?
        if let url = URL(string: artistURL), url.scheme != nil {
            resolved = url
        } else if let base = client?.config.baseURL {
            resolved = URL(string: artistURL, relativeTo: base)?.absoluteURL
        } else {
            resolved = nil
        }
        guard let resolved else { return .dead }
        // Artist URLs are resolved absolute URLs; key the disk cache by it so
        // repeated visits don't re-download full-resolution artwork.
        let cacheKey = CacheManager.metadataKey(endpoint: "artistImage",
                                                params: [URLQueryItem(name: "url", value: resolved.absoluteString)])
        if let cache, let data = await cache.readData(for: .covers, key: cacheKey),
           let image = decodeImage(from: data, requestedSize: size) {
            return .image(image)
        }
        guard client != nil else { return .dead }
        return await fetch(url: resolved, cacheKey: cacheKey, requestedSize: size)
    }

    /// Downloads cover art via `URLSession` (proper timeouts, cancellable),
    /// bounded by the concurrency gate. Classifies the outcome so transient
    /// failures never latch into `failedKeys`.
    func fetch(url: URL, cacheKey: String?, requestedSize: Int?) async -> FetchOutcome {
        guard !Task.isCancelled else { return .transient }
        coverLogger.debug("gate acquire url=\(url.absoluteString, privacy: .private)")
        let outcome = await gate.execute { [weak self] () -> FetchOutcome in
            guard let self, !Task.isCancelled else { return .transient }
            coverLogger.debug("gate acquired url=\(url.absoluteString, privacy: .private)")
            do {
                let (data, response) = try await self.session.data(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                    coverLogger.debug("fetch http \(code) url=\(url.absoluteString, privacy: .private)")
                    // 404 = genuinely missing art; anything else (500, auth) may
                    // recover, so don't latch it for the full TTL.
                    return code == 404 ? .dead : .transient
                }
                guard let image = self.decodeImage(from: data, requestedSize: requestedSize) else {
                    coverLogger.debug(
                        "fetch bad data url=\(url.absoluteString, privacy: .private) bytes=\(data.count)"
                    )
                    return .dead
                }
                // Validate BEFORE writing: an error payload (HTML/JSON behind a
                // 200, or truncated bytes) must never poison the disk cache.
                if let cacheKey, let cache = self.cache {
                    _ = try? await cache.write(data: data, to: .covers, key: cacheKey)
                }
                coverLogger.debug(
                    "fetch ok url=\(url.absoluteString, privacy: .private) bytes=\(data.count)"
                )
                return .image(image)
            } catch {
                // swiftlint:disable:next line_length
                coverLogger.error("fetch error url=\(url.absoluteString, privacy: .private) \(error.localizedDescription, privacy: .private)")
                return Self.classifyFetchError(error)
            }
        }
        return outcome ?? .transient
    }

    /// Maps a fetch throw to transient (retryable, never latched) vs dead.
    /// Covers cancellation explicitly: `URLSession` surfaces task-cancel as
    /// `URLError.cancelled`, and structured cancellation may surface as
    /// `CancellationError` — neither means the artwork is gone.
    static func classifyFetchError(_ error: Error) -> FetchOutcome {
        if error is CancellationError { return .transient }
        if Task.isCancelled { return .transient }
        guard let code = (error as? URLError)?.code else { return .dead }
        switch code {
        case .timedOut, .networkConnectionLost, .notConnectedToInternet, .cancelled:
            return .transient
        default:
            return .dead
        }
    }

    /// Decodes image data directly at target dimensions using ImageIO downsampling,
    /// preventing multi-megapixel full bitmaps from ever inflating in RAM.
    func decodeImage(from data: Data, requestedSize: Int?) -> NSImage? {
        let targetSide = requestedSize.map(CGFloat.init) ?? Self.maxDecodedSide
        let maxPixelSize = Int(targetSide)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return NSImage(data: data).map { bounded($0, requestedSize: requestedSize) }
        }
        if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }
        guard let fallback = NSImage(data: data) else { return nil }
        return bounded(fallback, requestedSize: requestedSize)
    }

    /// Downsamples artwork that exceeded its requested display size (or the
    /// `maxDecodedSide` cap for `.original`/artist URLs, which have no server
    /// size parameter) so the memory cache never holds multi-megapixel
    /// bitmaps. The disk cache still stores the full-resolution data; only
    /// the decoded in-memory representation is bounded.
    func bounded(_ image: NSImage, requestedSize: Int?) -> NSImage {
        let targetSide = requestedSize.map(CGFloat.init) ?? Self.maxDecodedSide
        let largest = max(image.size.width, image.size.height)
        guard largest > targetSide else { return image }
        let scale = targetSide / largest
        let targetSize = NSSize(width: image.size.width * scale,
                                height: image.size.height * scale)
        guard let ctx = CGContext(data: nil,
                                  width: max(1, Int(targetSize.width.rounded())),
                                  height: max(1, Int(targetSize.height.rounded())),
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        ctx.interpolationQuality = .high

        var proposedRect = CGRect(origin: .zero, size: image.size)
        if let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
            ?? (image.representations.compactMap { ($0 as? NSBitmapImageRep)?.cgImage }.first) {
            ctx.draw(cgImage, in: CGRect(origin: .zero, size: targetSize))
        } else {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            image.draw(in: CGRect(origin: .zero, size: targetSize))
            NSGraphicsContext.restoreGraphicsState()
        }
        guard let scaled = ctx.makeImage() else { return image }
        return NSImage(cgImage: scaled, size: targetSize)
    }
}
