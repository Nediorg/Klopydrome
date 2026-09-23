import XCTest
import AppKit
import Quartz
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
}
