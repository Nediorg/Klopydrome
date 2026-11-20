import Foundation
import SwiftData
import NavidromeClient

extension SwiftDataOfflineRepository {
    public static func serverDirectory(forServer host: String, create: Bool = false) -> URL {
        let safeHost = host
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        let appSupport = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: create
        ))?.appendingPathComponent("Klopydrome", isDirectory: true)
        let base = appSupport ?? FileManager.default.temporaryDirectory
        let serverDir = base.appendingPathComponent(safeHost.isEmpty ? "default" : safeHost, isDirectory: true)
        if create {
            try? FileManager.default.createDirectory(at: serverDir, withIntermediateDirectories: true)
        }
        return serverDir
    }

    public static func storeURL(forServer host: String) -> URL {
        let serverDir = serverDirectory(forServer: host, create: true)
        return serverDir.appendingPathComponent("OfflineLibrary.store")
    }

    private static func removeStoreFiles(at url: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: url)
        try? fm.removeItem(at: URL(fileURLWithPath: url.path + "-wal"))
        try? fm.removeItem(at: URL(fileURLWithPath: url.path + "-shm"))
    }

    public static func makeDefault(serverHost: String) throws -> SwiftDataOfflineRepository {
        let schema = Schema([
            OfflineArtist.self,
            OfflineAlbum.self,
            OfflineTrack.self,
            OfflinePlaylist.self,
            OfflinePlaylistEntry.self
        ])
        let storeLocation = storeURL(forServer: serverHost)
        let config = ModelConfiguration(schema: schema, url: storeLocation)
        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            return SwiftDataOfflineRepository(modelContainer: container)
        } catch {
            removeStoreFiles(at: storeLocation)
            let container = try ModelContainer(for: schema, configurations: [config])
            return SwiftDataOfflineRepository(modelContainer: container)
        }
    }

    public static func makeInMemory() throws -> SwiftDataOfflineRepository {
        let schema = Schema([
            OfflineArtist.self,
            OfflineAlbum.self,
            OfflineTrack.self,
            OfflinePlaylist.self,
            OfflinePlaylistEntry.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return SwiftDataOfflineRepository(modelContainer: container)
    }
}
