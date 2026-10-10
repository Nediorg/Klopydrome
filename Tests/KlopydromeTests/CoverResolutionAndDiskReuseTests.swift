import XCTest
import AppKit
import NavidromeClient
@testable import Klopydrome

final class CoverResolutionAndDiskReuseTests: XCTestCase {
    func testCoverResolutionBucketsAndRequestedSize() {
        let resolution = CoverResolution.high

        // Small thumbnails (song rows 36pt @2x = 72px, pills 40pt @2x = 80px, avatars 80pt @2x = 160px)
        XCTAssertEqual(resolution.requestedSize(forDisplayPixels: 72), 240)
        XCTAssertEqual(resolution.requestedSize(forDisplayPixels: 80), 240)
        XCTAssertEqual(resolution.requestedSize(forDisplayPixels: 160), 240)
        XCTAssertEqual(resolution.requestedSize(forDisplayPixels: 240), 240)

        // Cards and headers (shelves 165pt @2x = 330px, headers 220pt @2x = 440px)
        XCTAssertEqual(resolution.requestedSize(forDisplayPixels: 330), 720)
        XCTAssertEqual(resolution.requestedSize(forDisplayPixels: 440), 720)
        XCTAssertEqual(resolution.requestedSize(forDisplayPixels: 720), 720)

        // Candidate larger sizes for downsampling
        let largerFor240 = CoverResolution.candidateLargerSizes(than: 240)
        XCTAssertEqual(largerFor240, [720, 1200, 2048, 0])

        let largerFor720 = CoverResolution.candidateLargerSizes(than: 720)
        XCTAssertEqual(largerFor720, [1200, 2048, 0])
    }

    func testDiskReuseOfLargerCachedCoverWithoutNetwork() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CoverReuseTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let cache = CacheManager(rootURL: tempDir)
        let store = CoverArtStore.shared
        store.configure(client: nil, cache: cache, coverResolution: .high)

        let coverId = "reuse-test-\(UUID().uuidString)"

        // Generate a 720x720 dummy image data
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 720,
            pixelsHigh: 720,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        let image = NSImage(size: NSSize(width: 720, height: 720))
        image.addRepresentation(rep)
        guard let tiff = image.tiffRepresentation,
              let rep720 = NSBitmapImageRep(data: tiff),
              let jpegData = rep720.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            XCTFail("Failed to encode dummy JPEG")
            return
        }

        // Write 720.img directly to the disk cache
        let largeKey = CacheManager.coverKey(coverArt: coverId, size: 720)
        _ = try await cache.write(data: jpegData, to: .covers, key: largeKey)

        // Request a 240 thumbnail. Store has client = nil, so network fetch would fail/dead.
        let outcome = await store.resolveCover(coverArt: coverId, size: 240)

        // Should successfully resolve to the downsampled image
        guard case .image(let downsampled) = outcome else {
            XCTFail("Expected .image outcome from disk reuse")
            return
        }

        XCTAssertEqual(downsampled.size.width, 240, accuracy: 1.0)
        XCTAssertEqual(downsampled.size.height, 240, accuracy: 1.0)

        // Crucial: downsampled copy must NOT be written to disk (prevents duplication)
        let thumbKey = CacheManager.coverKey(coverArt: coverId, size: 240)
        let hasThumbOnDisk = await cache.hasFile(for: .covers, key: thumbKey)
        XCTAssertFalse(hasThumbOnDisk, "Downsampled thumbnail should not be duplicated onto disk")

        // Clean up store memory
        store.configure(client: nil, cache: nil)
    }

    func testOfflineDiskFallbackToSmallerCachedCoverWithoutNetwork() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CoverSmallerReuseTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let cache = CacheManager(rootURL: tempDir)
        let store = CoverArtStore.shared
        store.configure(client: nil, cache: cache, coverResolution: .high)

        let coverId = "smaller-reuse-test-\(UUID().uuidString)"
        guard let jpegData = makeDummyJPEG(width: 240, height: 240) else {
            XCTFail("Failed to encode dummy JPEG")
            return
        }

        // Only 240 is on disk
        let smallKey = CacheManager.coverKey(coverArt: coverId, size: 240)
        _ = try await cache.write(data: jpegData, to: .covers, key: smallKey)

        // Request 720 card in offline mode (client == nil)
        let outcome = await store.resolveCover(coverArt: coverId, size: 720)

        guard case .image(let resolved) = outcome else {
            XCTFail("Expected .image outcome from offline smaller disk fallback")
            return
        }

        XCTAssertNotNil(resolved)
        store.configure(client: nil, cache: nil)
    }

    func testOfflineDiskFallbackWhenOriginalRequestedWithoutNetwork() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CoverOrigReuseTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let cache = CacheManager(rootURL: tempDir)
        let store = CoverArtStore.shared
        store.configure(client: nil, cache: cache, coverResolution: .high)

        let coverId = "orig-reuse-test-\(UUID().uuidString)"
        guard let jpegData = makeDummyJPEG(width: 720, height: 720) else {
            XCTFail("Failed to encode dummy JPEG")
            return
        }

        // Only 720 is on disk
        let cardKey = CacheManager.coverKey(coverArt: coverId, size: 720)
        _ = try await cache.write(data: jpegData, to: .covers, key: cardKey)

        // Request original (size == nil) in offline mode (client == nil)
        let outcome = await store.resolveCover(coverArt: coverId, size: nil)

        guard case .image(let resolved) = outcome else {
            XCTFail("Expected .image outcome from offline original disk fallback")
            return
        }

        XCTAssertNotNil(resolved)
        store.configure(client: nil, cache: nil)
    }

    private func makeDummyJPEG(width: Int, height: Int) -> Data? {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(rep)
        guard let tiff = image.tiffRepresentation,
              let repImage = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return repImage.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    }
}
