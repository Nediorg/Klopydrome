import XCTest
import AppKit
import Quartz
import NavidromeClient
@testable import Klopydrome

final class QuickLookCoverTests: XCTestCase {
    func testCoverPreviewItemProperties() {
        let testURL = URL(fileURLWithPath: "/tmp/test-cover.jpg")
        let item = CoverPreviewItem(url: testURL, title: "Abbey Road")

        XCTAssertEqual(item.previewItemURL, testURL)
        XCTAssertEqual(item.previewItemTitle, "Abbey Road")
    }

    func testAnyCachedImageRetrieval() {
        let store = CoverArtStore.shared
        let coverId = "test-quicklook-\(UUID().uuidString)"

        // Initially nothing is cached
        XCTAssertNil(store.anyCachedImage(coverArt: coverId))

        // Cache a test image in memory directly
        let testImage = NSImage(size: NSSize(width: 100, height: 100))
        store.memory.setObject(testImage, forKey: "\(coverId)-orig" as NSString)
        store.lock.withLock {
            _ = store.cachedSizes[coverId, default: []].insert(0)
        }

        // anyCachedImage should find the cached image
        let retrieved = store.anyCachedImage(coverArt: coverId)
        XCTAssertNotNil(retrieved)

        // Clean up
        store.memory.removeObject(forKey: "\(coverId)-orig" as NSString)
        store.lock.withLock {
            _ = store.cachedSizes.removeValue(forKey: coverId)
        }
    }

    func testQuickLookFileURLFromInMemoryImage() async {
        let store = CoverArtStore.shared
        let coverId = "test-mem-\(UUID().uuidString)"

        // Create a 10x10 bitmap image and store in memory
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 10,
            pixelsHigh: 10,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        let image = NSImage(size: NSSize(width: 10, height: 10))
        image.addRepresentation(rep)

        store.memory.setObject(image, forKey: "\(coverId)-orig" as NSString)
        store.lock.withLock {
            _ = store.cachedSizes[coverId, default: []].insert(0)
        }

        let fileURL = await store.quickLookFileURL(coverArt: coverId, displayPixels: 100)
        XCTAssertNotNil(fileURL)
        if let fileURL {
            XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
            try? FileManager.default.removeItem(at: fileURL)
        }

        // Clean up
        store.memory.removeObject(forKey: "\(coverId)-orig" as NSString)
        store.lock.withLock {
            _ = store.cachedSizes.removeValue(forKey: coverId)
        }
    }

    func testCachedQuickLookFileURLFromDiskCache() async throws {
        let store = CoverArtStore.shared
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = CacheManager(rootURL: tempDir)
        store.configure(client: nil, cache: cache)

        let coverId = "test-disk-\(UUID().uuidString)"
        let dummyData = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46])
        let cacheKey = CacheManager.coverKey(coverArt: coverId, size: 720)
        _ = try await cache.write(data: dummyData, to: .covers, key: cacheKey)

        let url = store.cachedQuickLookFileURL(coverArt: coverId, displayPixels: 1000)
        XCTAssertNotNil(url)
        if let url {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            XCTAssertTrue(url.path.hasSuffix(".jpg"))
            let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey])
            XCTAssertNotEqual(values?.isSymbolicLink, true)
            XCTAssertEqual(values?.fileSize, dummyData.count)
            try? FileManager.default.removeItem(at: url)
        }
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testCachedQuickLookFileURLMultiSizeFallback() async throws {
        let store = CoverArtStore.shared
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = CacheManager(rootURL: tempDir)
        store.configure(client: nil, cache: cache)

        let coverId = "test-fallback-\(UUID().uuidString)"
        let dummyData = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let cacheKey = CacheManager.coverKey(coverArt: coverId, size: 240)
        _ = try await cache.write(data: dummyData, to: .covers, key: cacheKey)

        let url = store.cachedQuickLookFileURL(coverArt: coverId, displayPixels: 1000)
        XCTAssertNotNil(url)
        if let url {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            try? FileManager.default.removeItem(at: url)
        }
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testCachedQuickLookFileURLInMemoryFallback() {
        let store = CoverArtStore.shared
        let coverId = "test-mem-fallback-\(UUID().uuidString)"

        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 20,
            pixelsHigh: 20,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        let image = NSImage(size: NSSize(width: 20, height: 20))
        image.addRepresentation(rep)

        store.memory.setObject(image, forKey: "\(coverId)-orig" as NSString)
        store.lock.withLock {
            _ = store.cachedSizes[coverId, default: []].insert(0)
        }

        // Even with no disk cache configured, cachedQuickLookFileURL should write and return the file
        let url = store.cachedQuickLookFileURL(coverArt: coverId, displayPixels: 100)
        XCTAssertNotNil(url)
        if let url {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            try? FileManager.default.removeItem(at: url)
        }

        // Clean up
        store.memory.removeObject(forKey: "\(coverId)-orig" as NSString)
        store.lock.withLock {
            _ = store.cachedSizes.removeValue(forKey: coverId)
        }
    }

    func testTransitionImageReturnsNilForNaturalZoomScaling() {
        let view = QuickLookCover.NSQuickLookView()
        view.coverArt = "some-cover"

        var rect = NSRect.zero
        let result = withUnsafeMutablePointer(to: &rect) { ptr -> Any? in
            view.previewPanel(nil, transitionImageFor: nil, contentRect: ptr)
        }

        XCTAssertNil(result)
    }

    func testFullCoverFileURLResolvesFromDiskCache() async throws {
        let store = CoverArtStore.shared
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = CacheManager(rootURL: tempDir)
        store.configure(client: nil, cache: cache)

        let coverId = "test-full-\(UUID().uuidString)"
        let dummyData = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46])
        let fullKey = CacheManager.coverKey(coverArt: coverId, size: 0)
        _ = try await cache.write(data: dummyData, to: .covers, key: fullKey)

        let isCached = await store.isFullCoverCached(coverArt: coverId)
        XCTAssertTrue(isCached)

        let url = await store.fullCoverFileURL(coverArt: coverId)
        XCTAssertNotNil(url)
        if let url {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            XCTAssertTrue(url.path.hasSuffix("-full.jpg"))
            try? FileManager.default.removeItem(at: url)
        }
        try? FileManager.default.removeItem(at: tempDir)
    }
}
