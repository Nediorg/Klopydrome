import Foundation
import NavidromeClient
import AppKit
import os

let coverLogger = Logger(subsystem: "Klopydrome", category: "covers")

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

    /// Class wrapper so in-flight tasks can be identified and compared;
    /// `Task` itself is a struct. Only ever read under `lock`.
    private final class InflightTask: @unchecked Sendable {
        let id: UUID
        let task: Task<FetchOutcome, Never>
        var subscriberCount: Int = 1
        init(id: UUID = UUID(), _ task: Task<FetchOutcome, Never>) {
            self.id = id
            self.task = task
        }
    }

    /// Keeps concurrent network fetches bounded so a big cold grid can't spawn
    /// hundreds of simultaneous connections.
    private static let maxConcurrentFetches = 6

    /// Upper bound on decoded bitmaps held in memory. Artwork is costed at
    /// `width * height * 4` bytes, so a large grid can't pin hundreds of MB:
    /// beyond this the cache evicts least-recently-used entries (re-reads
    /// hit the disk cache, so the thrash cost is a cheap decode).
    private static let memoryCacheCostLimit = 384 << 20

    /// Largest decoded side for artwork requested without a pixel cap
    /// (`.original` covers, artist URLs). The disk cache keeps full quality;
    /// only the in-memory bitmap is bounded so a multi-megapixel cover can't
    /// occupy tens of MB of RAM.
    static let maxDecodedSide: CGFloat = 2048

    let memory = NSCache<NSString, NSImage>()
    private var inflight: [String: InflightTask] = [:]
    let lock = NSLock()

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
    var cachedSizes: [String: Set<Int>] = [:]

    let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config)
    }()

    /// Bounds concurrent network fetches without blocking a thread while
    /// waiting: suspended callers park in continuations instead.
    let gate = AsyncGate(capacity: CoverArtStore.maxConcurrentFetches)

    private(set) var client: SubsonicClient?
    private(set) var cache: CacheManager?
    private(set) var coverResolution: CoverResolution = .high

    private init() {
        memory.totalCostLimit = Self.memoryCacheCostLimit
        memory.countLimit = 1500
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
        if let exact = memory.object(forKey: key as NSString) {
            return exact
        }
        return largerCachedImage(for: coverArt, requested: requested)
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
                _ = cachedSizes[coverArt, default: []].insert(requested ?? 0)
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

    /// Synchronously retrieves an artist image from memory cache if present.
    func cachedArtistImage(artistURL: String?, size: Int) -> NSImage? {
        guard let artistURL, !artistURL.isEmpty else { return nil }
        let key = "artist-\(artistURL)-\(size)"
        return memory.object(forKey: key as NSString)
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
                existing.subscriberCount += 1
                return (false, existing)
            }
            let taskID = UUID()
            let task = Task<FetchOutcome, Never> { [weak self] in
                let outcome = await loader()
                self?.retireIfCurrent(key: key, taskID: taskID, outcome: outcome)
                return outcome
            }
            let holder = InflightTask(id: taskID, task)
            inflight[key] = holder
            return (true, holder)
        }

        let outcome = await withTaskCancellationHandler {
            await decision.holder.task.value
        } onCancel: { [weak self] in
            guard let self else { return }
            self.lock.withLock {
                decision.holder.subscriberCount -= 1
                if decision.holder.subscriberCount <= 0 {
                    decision.holder.task.cancel()
                    if self.inflight[key]?.id == decision.holder.id {
                        self.inflight.removeValue(forKey: key)
                    }
                }
            }
        }
        if case .image(let image) = outcome { return ImageBox(image: image) }
        return ImageBox(image: nil)
    }

    /// Retires a finished in-flight slot, recording the outcome. Only a
    /// still-current task may touch the registry: after a `configure` the key
    /// may already belong to the next server's task, which must not be
    /// disturbed. Extracted so `load()` stays under the complexity gate.
    private func retireIfCurrent(key: String, taskID: UUID, outcome: FetchOutcome) {
        let isCurrent = lock.withLock { () -> Bool in
            guard inflight[key]?.id == taskID else { return false }
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

    private static func cost(of image: NSImage) -> Int {
        // Approximate the decoded RGBA footprint (4 bytes/pixel). NSImage.size
        // is in points but for server artwork (no @2x scale info) it equals
        // pixel dimensions, so this is a fair byte estimate for eviction.
        let width = max(1, Int(image.size.width.rounded()))
        let height = max(1, Int(image.size.height.rounded()))
        return width * height * 4
    }
}
