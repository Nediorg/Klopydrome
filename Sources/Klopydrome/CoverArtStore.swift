import Foundation
import NavidromeClient
import AppKit
import os

private let coverLogger = Logger(subsystem: "Klopydrome", category: "covers")

/// Thread-safe, memory + disk cached cover artwork.
///
/// Views call the async `image(...)` methods. The work runs off the main
/// actor: disk reads, network fetches and image decodes happen on the
/// cooperative executor, so populating cover grids never blocks the UI.
///
/// The in-memory layer is an `NSCache` (thread-safe and self-bounding — it
/// evicts under memory pressure instead of growing without limit), and
/// concurrent requests for the same key share a single in-flight task rather
/// than each decoding the same artwork.
final class CoverArtStore: @unchecked Sendable {
    static let shared = CoverArtStore()

    /// `NSImage` isn't `Sendable`; box it so results can cross actor boundaries.
    struct ImageBox: @unchecked Sendable { let image: NSImage? }

    /// Class wrapper so in-flight tasks can be compared by identity (`===`);
    /// `Task` itself is a struct. Only ever read under `lock`.
    private final class InflightTask: @unchecked Sendable {
        let task: Task<FetchOutcome, Never>
        init(_ task: Task<FetchOutcome, Never>) { self.task = task }
    }

    /// Keeps concurrent network fetches bounded so a big cold grid can't spawn
    /// hundreds of simultaneous connections.
    private static let maxConcurrentFetches = 6

    /// Upper bound on decoded bitmaps held in memory. Artwork is costed at
    /// `width * height * 4` bytes, so a large grid can't pin hundreds of MB:
    /// beyond this the cache evicts least-recently-used entries (re-reads
    /// hit the disk cache, so the thrash cost is a cheap decode).
    private static let memoryCacheCostLimit = 64 << 20

    /// Largest decoded side for artwork requested without a pixel cap
    /// (`.original` covers, artist URLs). The disk cache keeps full quality;
    /// only the in-memory bitmap is bounded so a multi-megapixel cover can't
    /// occupy tens of MB of RAM.
    private static let maxDecodedSide: CGFloat = 2048

    private let memory = NSCache<NSString, NSImage>()
    private var inflight: [String: InflightTask] = [:]
    private let lock = NSLock()

    /// Artwork keys that failed to resolve. Each hit is returned instantly as
    /// `nil` so a dead or missing cover isn't re-requested on every
    /// scroll/revisit, and UI placeholders stop shimmering forever. Entries
    /// expire after `failedTTL` so a transient outage can recover. Only
    /// `.dead` outcomes are recorded here — transient failures (offline,
    /// timeout, cancellation) must never latch, or every background nap
    /// becomes minutes of dead tiles.
    private var failedKeys: [String: Date] = [:]
    private static let failedTTL: TimeInterval = 600

    /// Index of which sizes have been cached per coverArt, for the
    /// "use larger cached for smaller request" fallback. 0 represents
    /// original (nil requestedSize). Guarded by `lock`.
    private var cachedSizes: [String: Set<Int>] = [:]

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config)
    }()

    /// Bounds concurrent network fetches without blocking a thread while
    /// waiting: suspended callers park in continuations instead.
    private let gate = AsyncGate(capacity: CoverArtStore.maxConcurrentFetches)

    private var client: SubsonicClient?
    private var cache: CacheManager?
    private var coverResolution: CoverResolution = .high

    private init() {
        memory.totalCostLimit = Self.memoryCacheCostLimit
    }

    func configure(client: SubsonicClient?, cache: CacheManager?, coverResolution: CoverResolution = .high) {
        // A relaunch re-runs MainView's onAppear with the same client instance.
        // Cancelling in-flight fetches then would strand the LCD's cover request
        // (task(id:) never re-fires for an unchanged id), leaving it a placeholder.
        // Only a *different* client (a new server, or a reconnect with a fresh
        // client object) gets the reset.
        let toCancel: [InflightTask]? = lock.withLock {
            let identityChanged = self.client !== client
            self.client = client
            self.cache = cache
            self.coverResolution = coverResolution
            guard identityChanged else { return nil }
            // Cancelling the in-flight tasks guarantees no stale (previous-server)
            // result can later clobber the fresh registry or memory cache.
            memory.removeAllObjects()
            failedKeys.removeAll()
            let holders = Array(inflight.values)
            inflight.removeAll()
            return holders
        }
        if let toCancel {
            for holder in toCancel { holder.task.cancel() }
        }
    }

    func cachedImage(coverArt: String?, size: Int) -> NSImage? {
        guard let coverArt, !coverArt.isEmpty else { return nil }
        let requested = coverResolution.requestedSize(forDisplayPixels: size)
        let key = "\(coverArt)-\(requested.map(String.init) ?? "orig")"
        return memory.object(forKey: key as NSString)
    }

    /// File URL for the already-cached thumbnail (no network). Copied to a
    /// temp `.jpg` so Quick Look recognises it as image (cached file is `.img`).
    func cachedThumbnailFileURL(coverArt: String?, displayPixels: Int) async -> URL? {
        guard let coverArt, !coverArt.isEmpty, let cache else { return nil }
        let requested = coverResolution.requestedSize(forDisplayPixels: displayPixels)
        let cacheKey = CacheManager.coverKey(coverArt: coverArt, size: requested ?? 0)
        guard let data = await cache.readData(for: .covers, key: cacheKey) else { return nil }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("cover-thumb-\(coverArt).jpg")
        try? data.write(to: tmp, options: .atomic)
        return tmp
    }

    func image(coverArt: String?, size: Int) async -> ImageBox {
        guard let coverArt, !coverArt.isEmpty else { return ImageBox(image: nil) }
        let requested = coverResolution.requestedSize(forDisplayPixels: size)
        let key = "\(coverArt)-\(requested.map(String.init) ?? "orig")"
        // swiftlint:disable:next line_length
        coverLogger.debug("request coverArt=\(coverArt, privacy: .private) size=\(size) requested=\(requested.map(String.init) ?? "orig", privacy: .private) key=\(key, privacy: .private)")
        // Fast fallback: if exact size not in memory but a larger one is,
        // use it (downscaled by the view). Per requirement, never upscale:
        // a smaller cached image must not satisfy a larger request.
        if memory.object(forKey: key as NSString) == nil,
           let fallback = largerCachedImage(for: coverArt, requested: requested) {
            // swiftlint:disable:next line_length
            coverLogger.debug("fallback hit for \(coverArt, privacy: .private) \(requested.map(String.init) ?? "orig", privacy: .private) -> larger")
            return ImageBox(image: fallback)
        }
        let result = await load(key: key) { [weak self] in
            guard let self else { return .transient }
            return await self.resolveCover(coverArt: coverArt, size: requested)
        }
        if result.image != nil {
            coverLogger.debug("loaded coverArt=\(coverArt, privacy: .private) key=\(key, privacy: .private)")
            lock.withLock {
                cachedSizes[coverArt, default: []].insert(requested ?? 0)
            }
        } else {
            coverLogger.debug("miss coverArt=\(coverArt, privacy: .private) key=\(key, privacy: .private)")
        }
        return result
    }

    /// Returns a larger cached image for `coverArt` if one exists in memory,
    /// suitable for downscaling to `requested`. Never returns a smaller image
    /// for a larger request. `requested == nil` (original) has no larger.
    private func largerCachedImage(for coverArt: String, requested: Int?) -> NSImage? {
        guard let requested else { return nil }
        let sizes = lock.withLock { cachedSizes[coverArt] }
        guard let sizes, !sizes.isEmpty else { return nil }
        // Candidates larger than requested, plus original (0) as largest.
        // Pick the smallest larger to minimize over-fetch.
        let candidates = sizes.filter { $0 == 0 || $0 > requested }.sorted { lhs, rhs in
            // 0 (original) is considered largest, so it sorts last.
            if lhs == 0 { return false }
            if rhs == 0 { return true }
            return lhs < rhs
        }
        for size in candidates {
            let key = "\(coverArt)-\(size == 0 ? "orig" : String(size))"
            if let img = memory.object(forKey: key as NSString) {
                // Return as-is; the view's `scaledToFill` handles display
                // size, and we avoid a CoreGraphics downscale on the main
                // thread for every fallback hit (which would jank the toolbar).
                return img
            }
        }
        return nil
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
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("cover-\(coverArt).jpg")
        try? data.write(to: tmp, options: .atomic)
        return tmp
    }

    /// Loads an artist image from `artistImageUrl`. The URL may be absolute
    /// (server-provided) or a relative path resolved against the server base.
    func image(artistURL: String?, size: Int) async -> ImageBox {
        guard let artistURL, !artistURL.isEmpty else { return ImageBox(image: nil) }
        let key = "artist-\(artistURL)-\(size)"
        return await load(key: key) { [weak self] in
            guard let self else { return .transient }
            return await self.resolveArtist(artistURL: artistURL, size: size)
        }
    }

    /// Drops all negative-cache entries so the next lookup re-reads
    /// memory/disk and refetches. Called on foreground activation together
    /// with `foregroundRefreshRequested`, which pokes visible tiles (and
    /// errored grids) to re-request.
    func invalidateFailedKeys() {
        lock.withLock { failedKeys.removeAll() }
    }

    // MARK: - Core

    /// How a resolution attempt ended. Only `.dead` latches into `failedKeys`.
    enum FetchOutcome {
        case image(NSImage)
        case transient
        case dead
    }

    /// Returns the cached image or performs (and shares) a single load.
    /// `loader` runs off the main actor; only the memory cache and the
    /// in-flight registry are touched under the lock.
    private func load(key: String, loader: @escaping @Sendable () async -> FetchOutcome) async -> ImageBox {
        let isFailed = lock.withLock { () -> Bool in
            guard let date = failedKeys[key] else { return false }
            if Date().timeIntervalSince(date) < Self.failedTTL { return true }
            failedKeys.removeValue(forKey: key)
            return false
        }
        if isFailed {
            coverLogger.debug("blocked by failedKeys key=\(key, privacy: .private)")
            return ImageBox(image: nil)
        }
        if let image = memory.object(forKey: key as NSString) {
            coverLogger.debug("memory hit key=\(key, privacy: .private)")
            return ImageBox(image: image)
        }

        // `withLock` avoids raw lock/unlock calls inside async context. The
        // decision (new vs. shared task) is made synchronously under the lock.
        let decision: (isNew: Bool, holder: InflightTask) = lock.withLock {
            if let existing = inflight[key] {
                return (false, existing)
            }
            let holder = InflightTask(Task<FetchOutcome, Never> { await loader() })
            inflight[key] = holder
            return (true, holder)
        }

        let outcome = await decision.holder.task.value
        if decision.isNew {
            retireIfCurrent(key: key, holder: decision.holder, outcome: outcome)
        }
        if case .image(let image) = outcome { return ImageBox(image: image) }
        return ImageBox(image: nil)
    }

    /// Retires a finished in-flight slot, recording the outcome. Only a
    /// still-current task may touch the registry: after a `configure` the key
    /// may already belong to the next server's task, which must not be
    /// disturbed. Extracted so `load()` stays under the complexity gate.
    private func retireIfCurrent(key: String, holder: InflightTask, outcome: FetchOutcome) {
        let isCurrent = lock.withLock { () -> Bool in
            guard inflight[key] === holder else { return false }
            inflight.removeValue(forKey: key)
            return true
        }
        guard isCurrent else { return }
        switch outcome {
        case .image(let image):
            memory.setObject(image, forKey: key as NSString, cost: Self.cost(of: image))
        case .dead:
            // A genuinely failed resolution — remember it so later lookups short-circuit.
            lock.withLock {
                failedKeys[key] = Date()
                guard failedKeys.count > 512,
                      let oldest = failedKeys.min(by: { $0.value < $1.value })?.key else { return }
                failedKeys.removeValue(forKey: oldest)
            }
        case .transient:
            break // Never latch: offline/timeout/cancel must retry on the next lookup.
        }
    }

    private func resolveCover(coverArt: String, size: Int?) async -> FetchOutcome {
        let cacheKey = CacheManager.coverKey(coverArt: coverArt, size: size ?? 0)
        if let cache, let data = await cache.readData(for: .covers, key: cacheKey),
           let image = NSImage(data: data) {
            // swiftlint:disable:next line_length
            coverLogger.debug("disk hit coverArt=\(coverArt, privacy: .private) size=\(size.map(String.init) ?? "orig", privacy: .private)")
            return .image(bounded(image, requestedSize: size))
        }
        guard let client, let url = client.coverArtURL(id: coverArt, size: size) else {
            // swiftlint:disable:next line_length
            coverLogger.error("no client/url for coverArt=\(coverArt, privacy: .private) size=\(size.map(String.init) ?? "orig", privacy: .private)")
            return .dead
        }
        coverLogger.debug("fetch coverArt=\(coverArt, privacy: .private) url=\(url.absoluteString, privacy: .private)")
        return await fetch(url: url, cacheKey: cacheKey, requestedSize: size)
    }

    private func resolveArtist(artistURL: String, size: Int) async -> FetchOutcome {
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
    private func fetch(url: URL, cacheKey: String?, requestedSize: Int?) async -> FetchOutcome {
        coverLogger.debug("gate acquire url=\(url.absoluteString, privacy: .private)")
        guard await gate.acquire() else {
            coverLogger.debug("gate denied url=\(url.absoluteString, privacy: .private)")
            return .transient
        }
        coverLogger.debug("gate acquired url=\(url.absoluteString, privacy: .private)")
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                await gate.release()
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                coverLogger.debug("fetch http \(code) url=\(url.absoluteString, privacy: .private)")
                // 404 = genuinely missing art; anything else (500, auth) may
                // recover, so don't latch it for the full TTL.
                return code == 404 ? .dead : .transient
            }
            guard let image = NSImage(data: data) else {
                await gate.release()
                coverLogger.debug("fetch bad data url=\(url.absoluteString, privacy: .private) bytes=\(data.count)")
                return .dead
            }
            // Validate BEFORE writing: an error payload (HTML/JSON behind a
            // 200, or truncated bytes) must never poison the disk cache.
            if let cacheKey, let cache {
                _ = try? await cache.write(data: data, to: .covers, key: cacheKey)
            }
            let out = bounded(image, requestedSize: requestedSize)
            await gate.release()
            coverLogger.debug("fetch ok url=\(url.absoluteString, privacy: .private) bytes=\(data.count)")
            return .image(out)
        } catch {
            await gate.release()
            // swiftlint:disable:next line_length
            coverLogger.error("fetch error url=\(url.absoluteString, privacy: .private) \(error.localizedDescription, privacy: .private)")
            return Self.classifyFetchError(error)
        }
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

    private static func cost(of image: NSImage) -> Int {
        // Approximate the decoded RGBA footprint (4 bytes/pixel). NSImage.size
        // is in points but for server artwork (no @2x scale info) it equals
        // pixel dimensions, so this is a fair byte estimate for eviction.
        let width = max(1, Int(image.size.width.rounded()))
        let height = max(1, Int(image.size.height.rounded()))
        return width * height * 4
    }

    /// Downsamples artwork that exceeded its requested display size (or the
    /// `maxDecodedSide` cap for `.original`/artist URLs, which have no server
    /// size parameter) so the memory cache never holds multi-megapixel
    /// bitmaps. The disk cache still stores the full-resolution data; only
    /// the decoded in-memory representation is bounded.
    private func bounded(_ image: NSImage, requestedSize: Int?) -> NSImage {
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
