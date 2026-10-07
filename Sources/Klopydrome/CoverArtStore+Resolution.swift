import Foundation
import NavidromeClient
import AppKit
import CoreGraphics
import os

extension CoverArtStore {
    func resolveCover(coverArt: String, size: Int?) async -> FetchOutcome {
        let cacheKey = CacheManager.coverKey(coverArt: coverArt, size: size ?? 0)
        if let cache, let data = await cache.readData(for: .covers, key: cacheKey),
           let image = NSImage(data: data) {
            // swiftlint:disable:next line_length
            coverLogger.debug("disk hit coverArt=\(coverArt, privacy: .private) size=\(size.map(String.init) ?? "orig", privacy: .private)")
            return .image(bounded(image, requestedSize: size))
        }
        // Disk fallback: if exact size is missing on disk, inspect larger cached sizes
        // (e.g. 720, 1200, 0/orig) and downsample in memory without network or disk duplication.
        if let size, size > 0, let larger = await findLargerCachedCoverOnDisk(coverArt: coverArt, than: size) {
            return .image(larger)
        }
        guard let client else {
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
        return outcome
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
               let image = NSImage(data: data) {
                // swiftlint:disable:next line_length
                coverLogger.debug("disk reuse larger coverArt=\(coverArt, privacy: .private) found=\(largerSize) for=\(size)")
                let downsampled = bounded(image, requestedSize: size)
                lock.withLock {
                    _ = cachedSizes[coverArt, default: []].insert(size)
                }
                return downsampled
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
           let image = NSImage(data: data) {
            return .image(bounded(image, requestedSize: size))
        }
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
                guard let image = NSImage(data: data) else {
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
                let out = self.bounded(image, requestedSize: requestedSize)
                coverLogger.debug(
                    "fetch ok url=\(url.absoluteString, privacy: .private) bytes=\(data.count)"
                )
                return .image(out)
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
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let ctx = CGContext(data: nil,
                                  width: Int(targetSize.width.rounded()),
                                  height: Int(targetSize.height.rounded()),
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(cgImage, in: CGRect(origin: .zero, size: targetSize))
        guard let scaled = ctx.makeImage() else { return image }
        return NSImage(cgImage: scaled, size: targetSize)
    }
}
