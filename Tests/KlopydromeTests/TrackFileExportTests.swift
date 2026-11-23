import AppKit
import CoreTransferable
import Foundation
import NavidromeClient
import UniformTypeIdentifiers
import XCTest
@testable import Klopydrome

final class TrackFileExportTests: XCTestCase {
    func testExportFilenameFormattingAndSanitization() {
        let songWithArtist = SubsonicSong(
            id: "s-1",
            title: "Track: One/Two",
            artist: "Artist\\Alpha",
            suffix: "flac"
        )
        XCTAssertEqual(
            TrackDownload.exportFilename(for: songWithArtist),
            "Artist-Alpha - Track- One-Two.flac"
        )

        let songWithoutArtist = SubsonicSong(
            id: "s-2",
            title: "Solo Track",
            artist: nil,
            suffix: nil
        )
        XCTAssertEqual(
            TrackDownload.exportFilename(for: songWithoutArtist),
            "Solo Track.mp3"
        )

        XCTAssertEqual(
            TrackDownload.exportFilename(for: songWithArtist, fileExtension: "m4a"),
            "Artist-Alpha - Track- One-Two.m4a"
        )
    }

    func testPayloadExportInfoRoundTripAndGating() throws {
        let info = TrackDragPayload.ExportInfo(suggestedFilename: "Artist Alpha - Track 1.flac", canExport: true)
        let single = TrackDragPayload.song("s-1", exportInfo: info)
        let data = try JSONEncoder().encode(single)
        let decoded = try JSONDecoder().decode(TrackDragPayload.self, from: data)
        XCTAssertEqual(single, decoded)
        XCTAssertTrue(single.canExportSingleFile)

        let rawJSON = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(rawJSON.contains("http"))
        XCTAssertFalse(rawJSON.contains("token"))

        let multi = TrackDragPayload.songs(["s-1", "s-2"], exportInfo: info)
        XCTAssertFalse(multi.canExportSingleFile)
        XCTAssertNil(multi.exportInfo)

        let album = TrackDragPayload.album("alb-1")
        XCTAssertFalse(album.canExportSingleFile)

        let disabled = TrackDragPayload.song(
            "s-1",
            exportInfo: TrackDragPayload.ExportInfo(suggestedFilename: "Track 1.mp3", canExport: false)
        )
        XCTAssertFalse(disabled.canExportSingleFile)

        let queueItem = TrackDragPayload.queueItem(index: 0, songID: "s-1", exportInfo: info)
        XCTAssertTrue(queueItem.canExportSingleFile)

        let playlistTrack = TrackDragPayload.playlistTrack(
            playlistID: "pl-1",
            index: 0,
            songID: "s-1",
            exportInfo: info
        )
        XCTAssertTrue(playlistTrack.canExportSingleFile)
    }

    func testExportSingleTrackFromLocalCacheWithoutBlockingMainThread() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrackFileExportTests-\(UUID().uuidString)", isDirectory: true)
        let cacheRoot = tempRoot.appendingPathComponent("cache", isDirectory: true)
        let exportRoot = tempRoot.appendingPathComponent("exports", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let cache = CacheManager(rootURL: cacheRoot)
        let song = SubsonicSong(
            id: "s-cached",
            title: "Track/One",
            artist: "Artist:Alpha",
            suffix: "flac",
            duration: 1
        )
        let key = CacheManager.streamKey(songId: song.id, suffix: "flac")
        let audioBytes = makeValidFLACData(size: 8192)
        _ = try await cache.write(data: audioBytes, to: .streams, key: key)

        let exporter = TrackFileExporter(rootDirectory: exportRoot, ttl: 600)
        exporter.configure(environment: .init(
            cache: cache, client: nil, allowsNetworkRequests: false, configuredFormat: nil, maxBitRate: 0
        ))

        let info = TrackDragPayload.ExportInfo(
            suggestedFilename: TrackDownload.exportFilename(for: song, fileExtension: "flac"),
            canExport: true, suffix: song.suffix, duration: song.duration
        )
        let payload = TrackDragPayload.song(song.id, exportInfo: info)

        let transferred: SentTransferredFile = try await MainActor.run {
            let semaphore = DispatchSemaphore(value: 0)
            var result: Result<SentTransferredFile, Error>?
            Task.detached {
                do {
                    result = .success(try await exporter.exportSingleTrack(for: payload))
                } catch {
                    result = .failure(error)
                }
                semaphore.signal()
            }
            let waitResult = semaphore.wait(timeout: .now() + 5)
            XCTAssertEqual(waitResult, .success, "exportSingleTrack must not deadlock when main thread is blocked")
            return try XCTUnwrap(result).get()
        }

        XCTAssertEqual(transferred.file.lastPathComponent, "Artist-Alpha - Track-One.flac")
        XCTAssertTrue(transferred.file.path.hasPrefix(exportRoot.path))
        let exportedData = try Data(contentsOf: transferred.file)
        XCTAssertEqual(exportedData, audioBytes)
    }

    func testExportSingleTrackThrowsWhenOfflineAndUncached() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrackFileExportOffline-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let exporter = TrackFileExporter(rootDirectory: tempRoot, ttl: 600)
        exporter.configure(environment: TrackFileExporter.Environment(
            cache: nil,
            client: nil,
            allowsNetworkRequests: false,
            configuredFormat: nil,
            maxBitRate: 0
        ))

        let payload = TrackDragPayload.song(
            "s-missing",
            exportInfo: TrackDragPayload.ExportInfo(
                suggestedFilename: "Artist Beta - Track Two.mp3",
                canExport: true,
                suffix: "mp3",
                duration: 180
            )
        )
        do {
            _ = try await exporter.exportSingleTrack(for: payload)
            XCTFail("Expected TrackFileExportError.unavailable")
        } catch let error as TrackFileExportError {
            XCTAssertEqual(error, .unavailable)
        }
    }

    func testPruneExpiredDirectoriesRemovesOnlyStaleEntries() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrackFileExportPrune-\(UUID().uuidString)", isDirectory: true)
        let staleDir = tempRoot.appendingPathComponent("stale", isDirectory: true)
        let freshDir = tempRoot.appendingPathComponent("fresh", isDirectory: true)
        try FileManager.default.createDirectory(at: staleDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: freshDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let oldDate = Date().addingTimeInterval(-3600)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: staleDir.path)

        TrackFileExporter.pruneExpiredDirectories(in: tempRoot, olderThan: 600)

        XCTAssertFalse(FileManager.default.fileExists(atPath: staleDir.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: freshDir.path))
    }

    func testLocalCachedURLResolvesExistingFileAndReturnsNilForUncached() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrackFileLocalCached-\(UUID().uuidString)", isDirectory: true)
        let cacheRoot = tempRoot.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let cache = CacheManager(rootURL: cacheRoot)
        let audioBytes = makeValidFLACData(size: 8192)
        _ = try await cache.write(
            data: audioBytes,
            to: .streams,
            key: CacheManager.streamKey(songId: "s-local", suffix: "flac")
        )

        let exporter = TrackFileExporter(rootDirectory: tempRoot, ttl: 600)
        exporter.configure(environment: .init(
            cache: cache, client: nil, allowsNetworkRequests: false, configuredFormat: nil, maxBitRate: 0
        ))

        let info = TrackDragPayload.ExportInfo(
            suggestedFilename: "Artist Alpha - Track 1.flac",
            canExport: true,
            suffix: "flac",
            duration: 1
        )
        let found = exporter.localCachedURL(for: "s-local", info: info)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.pathExtension, "flac")

        let missing = exporter.localCachedURL(for: "s-other", info: info)
        XCTAssertNil(missing)
    }

    func testTrackFilePromiseProviderExposesInternalPayloadFirst() throws {
        let payload = TrackDragPayload.playlistTrack(
            playlistID: "pl-1",
            index: 3,
            songID: "s-1",
            exportInfo: .init(suggestedFilename: "Artist Alpha - Track 1.flac", canExport: true, suffix: "flac")
        )
        let provider = TrackFilePromiseProvider(
            payload: payload,
            suggestedFilename: "Artist Alpha - Track 1.flac"
        )
        let pasteboard = NSPasteboard.withUniqueName()
        let types = provider.writableTypes(for: pasteboard)
        let internalType = NSPasteboard.PasteboardType(UTType.trackDragPayload.identifier)
        XCTAssertEqual(types.first, internalType)

        let raw = try XCTUnwrap(provider.pasteboardPropertyList(forType: internalType) as? Data)
        let decoded = try JSONDecoder().decode(TrackDragPayload.self, from: raw)
        XCTAssertEqual(decoded, payload)
    }

    private func makeValidFLACData(size: Int) -> Data {
        var bytes = [UInt8](repeating: 0xAA, count: max(size, 4096))
        bytes[0] = 0x66
        bytes[1] = 0x4C
        bytes[2] = 0x61
        bytes[3] = 0x43
        return Data(bytes)
    }
}
