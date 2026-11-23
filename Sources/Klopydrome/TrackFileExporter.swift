import CoreTransferable
import Foundation
import NavidromeClient
import os

enum TrackFileExportError: Error, Equatable {
    case notConfigured
    case multiTrackUnsupported
    case unavailable
    case invalidAudioFile
}

final class TrackFileExporter: Sendable {
    struct Environment: Sendable {
        var cache: CacheManager?
        var client: SubsonicClient?
        var allowsNetworkRequests: Bool
        var configuredFormat: String?
        var maxBitRate: Int
    }

    static let shared = TrackFileExporter()
    static let defaultTTL: TimeInterval = 600

    static var exportRootDirectory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("KlopydromeDragExports", isDirectory: true)
    }

    private let environment = OSAllocatedUnfairLock<Environment?>(initialState: nil)
    private let rootDirectory: URL
    private let ttl: TimeInterval

    init(
        rootDirectory: URL = TrackFileExporter.exportRootDirectory,
        ttl: TimeInterval = TrackFileExporter.defaultTTL
    ) {
        self.rootDirectory = rootDirectory
        self.ttl = ttl
    }

    func configure(environment: Environment) {
        self.environment.withLock { $0 = environment }
        let root = rootDirectory
        let maxAge = ttl
        Task.detached(priority: .utility) {
            Self.pruneExpiredDirectories(in: root, olderThan: maxAge)
        }
    }

    func updateEnvironment(_ environment: Environment) {
        self.environment.withLock { $0 = environment }
    }

    func localCachedURL(for songID: String, info: TrackDragPayload.ExportInfo) -> URL? {
        guard let env = environment.withLock({ $0 }) else { return nil }
        return cachedFileURL(for: songID, info: info, env: env)
    }

    func downloadRemoteURL(for songID: String) -> URL? {
        guard let env = environment.withLock({ $0 }), env.allowsNetworkRequests else { return nil }
        return env.client?.downloadURL(songId: songID, maxBitRate: 0, format: "raw")
    }

    func downloadTrack(for payload: TrackDragPayload, to destinationURL: URL) async throws {
        guard payload.canExportSingleFile,
              let songID = payload.singleSongID,
              let remoteURL = downloadRemoteURL(for: songID) else {
            throw TrackFileExportError.unavailable
        }
        try await TrackDownload.transferFile(remoteURL, to: destinationURL)
    }

    func exportSingleTrack(for payload: TrackDragPayload) async throws -> SentTransferredFile {
        guard payload.canExportSingleFile,
              let songID = payload.singleSongID,
              let info = payload.exportInfo else {
            throw TrackFileExportError.multiTrackUnsupported
        }
        guard let env = environment.withLock({ $0 }) else {
            throw TrackFileExportError.notConfigured
        }

        let source = try resolveSource(songID: songID, info: info, env: env)
        let stagingDir = rootDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let stagedURL = stagingDir.appendingPathComponent(source.filename)

        Self.pruneExpiredDirectories(in: rootDirectory, olderThan: ttl)
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        do {
            try await Self.materialize(source: source, to: stagedURL)
        } catch {
            try? FileManager.default.removeItem(at: stagingDir)
            throw error
        }

        scheduleCleanup(for: stagingDir, after: ttl)
        return SentTransferredFile(stagedURL, allowAccessingOriginalFile: false)
    }

    private enum ExportSource: Sendable {
        case cached(url: URL, filename: String)
        case remote(url: URL, filename: String)

        var filename: String {
            switch self {
            case .cached(_, let name), .remote(_, let name):
                return name
            }
        }
    }

    private func resolveSource(
        songID: String,
        info: TrackDragPayload.ExportInfo,
        env: Environment
    ) throws -> ExportSource {
        if let cached = cachedFileURL(for: songID, info: info, env: env) {
            let ext = cached.pathExtension.isEmpty ? nil : cached.pathExtension
            let name = Self.filename(from: info.suggestedFilename, replacingExtension: ext)
            return .cached(url: cached, filename: name)
        }
        if env.allowsNetworkRequests,
           let remote = env.client?.downloadURL(songId: songID, maxBitRate: 0, format: "raw") {
            let name = Self.filename(from: info.suggestedFilename, replacingExtension: info.suffix)
            return .remote(url: remote, filename: name)
        }
        throw TrackFileExportError.unavailable
    }

    private func cachedFileURL(
        for songID: String,
        info: TrackDragPayload.ExportInfo,
        env: Environment
    ) -> URL? {
        guard let cache = env.cache else { return nil }
        let minBytes = Self.minimumExpectedCacheBytes(duration: info.duration)
        let suffixes = Self.candidateSuffixes(
            songSuffix: info.suffix,
            configuredFormat: env.configuredFormat,
            maxBitRate: env.maxBitRate
        )
        for suffix in suffixes {
            let key = CacheManager.streamKey(songId: songID, suffix: suffix)
            let url = cache.fileURL(for: .streams, key: key)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
               size >= minBytes {
                return url
            }
        }
        return nil
    }

    private static func minimumExpectedCacheBytes(duration: Int?) -> Int {
        if let duration, duration > 0 {
            return max(4096, Int(Double(duration) * 1500 * 0.75))
        }
        return 4096
    }

    private static func candidateSuffixes(
        songSuffix: String?,
        configuredFormat: String?,
        maxBitRate: Int
    ) -> [String] {
        var suffixes: [String] = []
        if let format = configuredFormat?.trimmingCharacters(in: .whitespacesAndNewlines), !format.isEmpty {
            suffixes.append(format.lowercased())
        } else if maxBitRate > 0 {
            suffixes.append("mp3")
        }
        if let songSuffix = songSuffix?.trimmingCharacters(in: .whitespacesAndNewlines), !songSuffix.isEmpty {
            suffixes.append(songSuffix.lowercased())
        }
        suffixes.append(contentsOf: ["mp3", "flac", "m4a", "opus", "ogg", "wav", "aac"])
        var seen = Set<String>()
        return suffixes.filter { seen.insert($0).inserted }
    }

    private static func filename(from suggested: String, replacingExtension ext: String?) -> String {
        guard let ext = ext?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !ext.isEmpty else {
            return suggested
        }
        let url = URL(fileURLWithPath: suggested)
        if url.pathExtension.lowercased() == ext {
            return suggested
        }
        if url.pathExtension.isEmpty {
            return "\(suggested).\(ext)"
        }
        return url.deletingPathExtension().appendingPathExtension(ext).lastPathComponent
    }

    private static func materialize(source: ExportSource, to destination: URL) async throws {
        switch source {
        case .cached(let cachedURL, _):
            try FileManager.default.copyItem(at: cachedURL, to: destination)
        case .remote(let remoteURL, _):
            try await TrackDownload.transferFile(remoteURL, to: destination)
        }
    }

    private func scheduleCleanup(for directory: URL, after delay: TimeInterval) {
        guard delay > 0 else { return }
        Task.detached(priority: .background) {
            try? await Task.sleep(for: .seconds(delay))
            try? FileManager.default.removeItem(at: directory)
        }
    }

    static func pruneExpiredDirectories(in root: URL, olderThan maxAge: TimeInterval) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-maxAge)
        for entry in entries {
            let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            if modified < cutoff {
                try? fm.removeItem(at: entry)
            }
        }
    }
}
