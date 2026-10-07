import Foundation
import SwiftData
import NavidromeClient

extension SwiftDataOfflineRepository {
    public static func storeURL(forServer host: String) -> URL {
        let safeHost = host
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        let appSupport = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ))?.appendingPathComponent("Klopydrome", isDirectory: true)
        let base = appSupport ?? FileManager.default.temporaryDirectory
        let serverDir = base.appendingPathComponent(safeHost.isEmpty ? "default" : safeHost, isDirectory: true)
        try? FileManager.default.createDirectory(at: serverDir, withIntermediateDirectories: true)
        return serverDir.appendingPathComponent("OfflineLibrary.store")
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
        let config = ModelConfiguration(url: storeLocation)
        let container = try ModelContainer(for: schema, configurations: [config])
        return SwiftDataOfflineRepository(modelContainer: container)
    }

    public static func makeInMemory() throws -> SwiftDataOfflineRepository {
        let schema = Schema([
            OfflineArtist.self,
            OfflineAlbum.self,
            OfflineTrack.self,
            OfflinePlaylist.self,
            OfflinePlaylistEntry.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return SwiftDataOfflineRepository(modelContainer: container)
    }
}
