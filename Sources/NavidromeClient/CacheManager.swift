import Foundation
import CryptoKit

public enum CacheKind: String, CaseIterable, Sendable {
    case covers
    case streams
    case metadata
}

public struct CacheLimits: Codable, Equatable, Sendable {
    public var maxTotalBytes: Int
    public var maxCoversBytes: Int
    public var maxStreamsBytes: Int
    public var maxMetadataBytes: Int

    public init(maxTotalBytes: Int = Self.default.maxTotalBytes,
                maxCoversBytes: Int = Self.default.maxCoversBytes,
                maxStreamsBytes: Int = Self.default.maxStreamsBytes,
                maxMetadataBytes: Int = Self.default.maxMetadataBytes) {
        self.maxTotalBytes = maxTotalBytes
        self.maxCoversBytes = maxCoversBytes
        self.maxStreamsBytes = maxStreamsBytes
        self.maxMetadataBytes = maxMetadataBytes
    }

    public static let `default` = CacheLimits(
        maxTotalBytes: 2_000_000_000,
        maxCoversBytes: 200_000_000,
        maxStreamsBytes: 1_500_000_000,
        maxMetadataBytes: 30_000_000
    )
}

public actor CacheManager {
    public let rootURL: URL
    private var _limits: CacheLimits

    private let fileManager = FileManager.default
    private var kindTotals: [CacheKind: Int] = [:]
    private var totalsLoaded = false

    private var discographyByArtist: [String: [SubsonicSong]] = [:]
    private var discographyArtistOrder: [String] = []
    private let maxDiscographyArtists = 25

    public init(rootURL: URL? = nil, limits: CacheLimits = .default) {
        let base = rootURL
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("NavidromeSwift", isDirectory: true)
        self.rootURL = base
        self._limits = limits
        for kind in CacheKind.allCases {
            try? FileManager.default.createDirectory(at: directory(for: kind),
                                                     withIntermediateDirectories: true)
        }
    }

    public var limits: CacheLimits {
        get { _limits }
        set { _limits = newValue }
    }

    public func setLimits(_ newLimits: CacheLimits) {
        _limits = newLimits
    }

    public nonisolated static func root(forServer host: String) -> URL {
        let safeHost = host
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        let caches = (try? FileManager.default.url(for: .cachesDirectory,
                                                    in: .userDomainMask,
                                                    appropriateFor: nil,
                                                    create: true))?
            .appendingPathComponent("NavidromeSwift", isDirectory: true)
        let base = caches ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(safeHost, isDirectory: true)
    }

    public nonisolated func directory(for kind: CacheKind) -> URL {
        rootURL.appendingPathComponent(kind.rawValue, isDirectory: true)
    }

    public nonisolated func fileURL(for kind: CacheKind, key: String) -> URL {
        directory(for: kind).appendingPathComponent(sanitize(key))
    }

    public nonisolated static func coverKey(coverArt: String, size: Int) -> String {
        "\(coverArt)-\(size).img"
    }

    public nonisolated static func streamKey(songId: String, suffix: String) -> String {
        "\(songId).\(suffix)"
    }

    public nonisolated static func metadataKey(endpoint: String, params: [URLQueryItem]) -> String {
        let seed = params
            .sorted { $0.name < $1.name }
            .map { "\($0.name)=\($0.value ?? "")" }
            .joined(separator: "&")
        return "\(endpoint)#\(Self.sha256(seed).prefix(16))"
    }

    private nonisolated static func sha256(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated func sanitize(_ key: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let cleaned = String(key.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        let collapsed = cleaned.replacingOccurrences(of: #"\.+"#, with: ".", options: .regularExpression)
        var trimmed = collapsed
        while trimmed.hasPrefix(".") {
            trimmed.removeFirst()
        }
        return trimmed.isEmpty ? "unnamed" : trimmed
    }

    public func fileKeys(for kind: CacheKind) -> [String] {
        let dir = directory(for: kind)
        return (try? fileManager.contentsOfDirectory(atPath: dir.path)) ?? []
    }

    public func hasFile(for kind: CacheKind, key: String) async -> Bool {
        fileManager.fileExists(atPath: fileURL(for: kind, key: key).path)
    }

    public func readData(for kind: CacheKind, key: String) async -> Data? {
        let url = fileURL(for: kind, key: key)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        if kind == .streams {
            try? fileManager.setAttributes([.modificationDate: Date()],
                                           ofItemAtPath: url.path)
        }
        return try? Data(contentsOf: url)
    }

    @discardableResult
    public func write(data: Data, to kind: CacheKind, key: String) async throws -> URL {
        let url = fileURL(for: kind, key: key)
        try data.write(to: url, options: .atomic)
        addBytes(data.count, to: kind)
        await evictIfNeeded()
        return url
    }

    @discardableResult
    public func moveFile(from source: URL, to kind: CacheKind, key: String) async throws -> URL {
        let url = fileURL(for: kind, key: key)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try fileManager.moveItem(at: source, to: url)
        addBytes(fileSize(url), to: kind)
        await evictIfNeeded()
        return url
    }

    public func removeFile(for kind: CacheKind, key: String) {
        let url = fileURL(for: kind, key: key)
        let size = fileSize(url)
        if (try? fileManager.removeItem(at: url)) != nil {
            addBytes(-size, to: kind)
        }
    }

    public func clear() async {
        for kind in CacheKind.allCases {
            await clear(kind: kind)
        }
        discographyByArtist = [:]
        discographyArtistOrder = []
    }

    public func clear(kind: CacheKind) async {
        let dir = directory(for: kind)
        guard let files = try? fileManager.contentsOfDirectory(atPath: dir.path) else { return }
        for file in files {
            try? fileManager.removeItem(atPath: dir.appendingPathComponent(file).path)
        }
        kindTotals[kind] = 0
    }

    public func cachedDiscography(for artistId: String) async -> [SubsonicSong]? {
        discographyByArtist[artistId]
    }

    public func cacheDiscography(_ songs: [SubsonicSong], for artistId: String) async {
        discographyByArtist[artistId] = songs
        if let idx = discographyArtistOrder.firstIndex(of: artistId) {
            discographyArtistOrder.remove(at: idx)
        }
        discographyArtistOrder.append(artistId)
        while discographyArtistOrder.count > maxDiscographyArtists {
            let evicted = discographyArtistOrder.removeFirst()
            discographyByArtist.removeValue(forKey: evicted)
        }
    }

    private func totalBytes() -> Int {
        CacheKind.allCases.reduce(0) { $0 + (kindTotals[$1] ?? 0) }
    }

    public func totalBytesAsync() async -> Int {
        await ensureTotals()
        return totalBytes()
    }

    private func bytes(for kind: CacheKind) -> Int {
        kindTotals[kind] ?? 0
    }

    public func bytesAsync(for kind: CacheKind) async -> Int {
        await ensureTotals()
        return bytes(for: kind)
    }

    private nonisolated static func scanStoreBytes(in directory: URL) -> Int {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey, .fileSizeKey]
        ) else { return 0 }
        let entries = urls.compactMap { url -> Int? in
            guard let values = try? url.resourceValues(forKeys: [
                .contentModificationDateKey, .isRegularFileKey, .fileSizeKey
            ]), values.isRegularFile == true else { return nil }
            return values.fileSize
        }
        return entries.reduce(0, +)
    }

    private func addBytes(_ delta: Int, to kind: CacheKind) {
        kindTotals[kind, default: 0] = max(0, (kindTotals[kind, default: 0]) + delta)
    }

    private func ensureTotals() async {
        guard !totalsLoaded else { return }
        let directories = CacheKind.allCases.map { ($0, directory(for: $0)) }
        let scanned: [CacheKind: Int] = await withTaskGroup(of: (CacheKind, Int).self) { group in
            for (kind, dir) in directories {
                group.addTask {
                    (kind, Self.scanStoreBytes(in: dir))
                }
            }
            var result: [CacheKind: Int] = [:]
            for await (kind, count) in group {
                result[kind] = count
            }
            return result
        }
        if !totalsLoaded {
            kindTotals = scanned
            totalsLoaded = true
        }
    }

    private func scanBytes(_ kind: CacheKind) -> Int {
        var total = 0
        for entry in files(in: kind) {
            total += entry.size
        }
        return total
    }

    private func evictIfNeeded() async {
        await ensureTotals()
        for kind in CacheKind.allCases {
            let limit = kindLimit(kind)
            if (kindTotals[kind] ?? 0) > limit { await evict(kind, toTarget: limit) }
        }
        if totalBytes() > limits.maxTotalBytes {
            await evict(totalTarget: limits.maxTotalBytes)
        }
    }

    private func kindLimit(_ kind: CacheKind) -> Int {
        switch kind {
        case .covers: return limits.maxCoversBytes
        case .streams: return limits.maxStreamsBytes
        case .metadata: return limits.maxMetadataBytes
        }
    }

    private struct CacheFileEntry {
        let url: URL
        let date: Date
        let size: Int
    }

    private struct GlobalEvictEntry {
        let kind: CacheKind
        let url: URL
        let date: Date
        let size: Int
    }

    private func files(in kind: CacheKind) -> [CacheFileEntry] {
        let dir = directory(for: kind)
        guard let urls = try? fileManager.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey, .fileSizeKey]
        ) else { return [] }
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: [
                .contentModificationDateKey, .isRegularFileKey, .fileSizeKey
            ]), values.isRegularFile == true, let date = values.contentModificationDate else {
                return nil
            }
            return CacheFileEntry(url: url, date: date, size: values.fileSize ?? 0)
        }.sorted { $0.date < $1.date }
    }

    private func evict(_ kind: CacheKind, toTarget target: Int) async {
        let entries = files(in: kind)
        var total = entries.reduce(0) { $0 + $1.size }
        guard total > target else { return }
        for entry in entries {
            if total <= target { break }
            if (try? fileManager.removeItem(at: entry.url)) != nil {
                total -= entry.size
            }
        }
        kindTotals[kind] = max(0, total)
    }

    private func evict(totalTarget target: Int) async {
        let all: [GlobalEvictEntry] = CacheKind.allCases.reduce(into: []) { acc, kind in
            for entry in files(in: kind) {
                acc.append(GlobalEvictEntry(kind: kind, url: entry.url, date: entry.date, size: entry.size))
            }
        }.sorted { $0.date < $1.date }
        var total = all.reduce(0) { $0 + $1.size }
        guard total > target else { return }
        var removedByKind: [CacheKind: Int] = [:]
        for entry in all {
            if total <= target { break }
            if (try? fileManager.removeItem(at: entry.url)) != nil {
                total -= entry.size
                removedByKind[entry.kind, default: 0] += entry.size
            }
        }
        for (kind, removed) in removedByKind {
            kindTotals[kind] = max(0, (kindTotals[kind] ?? 0) - removed)
        }
    }

    private func fileSize(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
    }
}
