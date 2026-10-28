import Foundation
import NavidromeClient
import AppKit
import os

let coverLogger = Logger(subsystem: "Klopydrome", category: "covers")

final class CoverArtStore: @unchecked Sendable {
    static let shared = CoverArtStore()

    struct ImageBox: @unchecked Sendable { let image: NSImage? }

    private final class InflightTask: @unchecked Sendable {
        let id: UUID
        let task: Task<FetchOutcome, Never>
        var subscriberCount: Int = 1
        init(id: UUID = UUID(), _ task: Task<FetchOutcome, Never>) {
            self.id = id
            self.task = task
        }
    }

    private static let maxConcurrentFetches = 6

    private static var memoryCacheCostLimit: Int {
        let mem = ProcessInfo.processInfo.physicalMemory
        return max(96 << 20, min(256 << 20, Int(mem / 64)))
    }
    private static let memoryCacheCountLimit = 1_000

    static let maxDecodedSide: CGFloat = 2048

    let memory = NSCache<NSString, NSImage>()
    private var inflight: [String: InflightTask] = [:]
    let lock = NSLock()

    private var failedKeys: [String: Date] = [:]
    private static let failedTTL: TimeInterval = 600

    var cachedSizes: [String: Set<Int>] = [:]

    let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config)
    }()

    let gate = AsyncGate(capacity: CoverArtStore.maxConcurrentFetches)

    private(set) var client: SubsonicClient?
    private(set) var cache: CacheManager?
    private(set) var coverResolution: CoverResolution = .high
    private(set) var adaptiveCellularDataEnabled: Bool = true

    var effectiveCoverResolution: CoverResolution {
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            return .low
        }
        if adaptiveCellularDataEnabled && NetworkMonitor.shared.isConstrainedOrExpensive {
            return .low
        }
        return coverResolution
    }

    private init() {
        memory.totalCostLimit = Self.memoryCacheCostLimit
        memory.countLimit = Self.memoryCacheCountLimit
    }

    func configure(
        client: SubsonicClient?,
        cache: CacheManager?,
        coverResolution: CoverResolution? = nil,
        adaptiveCellularDataEnabled: Bool? = nil
    ) {
        let (toCancel, shouldNotify): ([InflightTask]?, Bool) = lock.withLock {
            let identityChanged = self.client !== client
            let clientBecameAvailable = self.client == nil && client != nil
            self.client = client
            self.cache = cache
            if let coverResolution {
                self.coverResolution = coverResolution
            }
            if let adaptiveCellularDataEnabled {
                self.adaptiveCellularDataEnabled = adaptiveCellularDataEnabled
            }
            guard identityChanged else { return (nil, false) }
            if !clientBecameAvailable {
                memory.removeAllObjects()
            }
            failedKeys.removeAll()
            cachedSizes.removeAll()
            let holders = Array(inflight.values)
            inflight.removeAll()
            return (holders, true)
        }
        if let toCancel {
            for holder in toCancel { holder.task.cancel() }
        }
        if shouldNotify {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .foregroundRefreshRequested, object: nil)
            }
        }
    }

    func clearMemoryCache() {
        lock.withLock {
            memory.removeAllObjects()
            failedKeys.removeAll()
            cachedSizes.removeAll()
        }
    }

    func cachedImage(coverArt: String?, size: Int) -> NSImage? {
        guard let coverArt, !coverArt.isEmpty else { return nil }
        let requested = effectiveCoverResolution.requestedSize(forDisplayPixels: size)
        let key = "\(coverArt)-\(requested.map(String.init) ?? "orig")"
        if let exact = memory.object(forKey: key as NSString) {
            return exact
        }
        guard let fallback = largerCachedImage(for: coverArt, requested: requested) else { return nil }
        return fallback
    }

    func image(coverArt: String?, size: Int) async -> ImageBox {
        guard let coverArt, !coverArt.isEmpty else { return ImageBox(image: nil) }
        let requested = effectiveCoverResolution.requestedSize(forDisplayPixels: size)
        let key = "\(coverArt)-\(requested.map(String.init) ?? "orig")"
        coverLogger.debug(
            "request coverArt=\(coverArt, privacy: .private) size=\(size) requested=\(requested.map(String.init) ?? "orig", privacy: .private) key=\(key, privacy: .private)"
        )
        if memory.object(forKey: key as NSString) == nil,
           let fallback = largerCachedImage(for: coverArt, requested: requested) {
            coverLogger.debug(
                "fallback hit for \(coverArt, privacy: .private) \(requested.map(String.init) ?? "orig", privacy: .private) -> larger"
            )
            let targetSize = requested ?? size
            if fallback.size.width > CGFloat(targetSize) * 1.5 || fallback.size.height > CGFloat(targetSize) * 1.5 {
                let downscaled = bounded(fallback, requestedSize: targetSize)
                memory.setObject(downscaled, forKey: key as NSString, cost: Self.cost(of: downscaled))
                lock.withLock {
                    _ = cachedSizes[coverArt, default: []].insert(targetSize)
                }
                return ImageBox(image: downscaled)
            }
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

    private func largerCachedImage(for coverArt: String, requested: Int?) -> NSImage? {
        guard let requested else { return nil }
        let sizes = lock.withLock { cachedSizes[coverArt] }
        guard let sizes, !sizes.isEmpty else { return nil }
        let candidates = sizes.filter { $0 == 0 || $0 > requested }.sorted { lhs, rhs in
            if lhs == 0 { return false }
            if rhs == 0 { return true }
            return lhs < rhs
        }
        for size in candidates {
            let key = "\(coverArt)-\(size == 0 ? "orig" : String(size))"
            if let img = memory.object(forKey: key as NSString) {
                return img
            }
        }
        return nil
    }

    func cachedArtistImage(artistURL: String?, size: Int) -> NSImage? {
        guard let artistURL, !artistURL.isEmpty else { return nil }
        let key = "artist-\(artistURL)-\(size)"
        return memory.object(forKey: key as NSString)
    }

    func image(artistURL: String?, size: Int) async -> ImageBox {
        guard let artistURL, !artistURL.isEmpty else { return ImageBox(image: nil) }
        let key = "artist-\(artistURL)-\(size)"
        return await load(key: key) { [weak self] in
            guard let self else { return .transient }
            return await self.resolveArtist(artistURL: artistURL, size: size)
        }
    }

    func invalidateFailedKeys() {
        lock.withLock { failedKeys.removeAll() }
    }

    enum FetchOutcome {
        case image(NSImage)
        case transient
        case dead
    }

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
        let width = max(1, Int(image.size.width.rounded()))
        let height = max(1, Int(image.size.height.rounded()))
        return width * height * 4
    }
}
