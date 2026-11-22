import XCTest
@testable import Klopydrome

/// `MiniPlayerResizeGeometry.contentSize` applies to the OPEN detail panel
/// only. The collapsed square is enforced natively by the panel's 1:1
/// `contentAspectRatio` and is intentionally not re-derived here.
final class MiniPlayerResizeGeometryTests: XCTestCase {

    func testVerticalResizeStretchesPanelAndKeepsArtworkWidth() {
        let size = MiniPlayerResizeGeometry.contentSize(
            requested: NSSize(width: 420, height: 900),
            current: NSSize(width: 420, height: 720)
        )

        XCTAssertEqual(size.width, 420, accuracy: 0.001)
        XCTAssertEqual(size.height, 900, accuracy: 0.001)
        XCTAssertEqual(size.height - size.width, 480, accuracy: 0.001)
    }

    func testHorizontalResizeKeepsWindowHeightAndPanelGivesUpSpace() {
        let size = MiniPlayerResizeGeometry.contentSize(
            requested: NSSize(width: 560, height: 800),
            current: NSSize(width: 420, height: 800)
        )

        XCTAssertEqual(size.width, 560, accuracy: 0.001)
        XCTAssertEqual(size.height, 800, accuracy: 0.001)
        XCTAssertEqual(size.height - size.width, 240, accuracy: 0.001)
    }

    func testHorizontalShrinkReturnsSpaceToThePanel() {
        let size = MiniPlayerResizeGeometry.contentSize(
            requested: NSSize(width: 380, height: 800),
            current: NSSize(width: 420, height: 800)
        )

        XCTAssertEqual(size.width, 380, accuracy: 0.001)
        XCTAssertEqual(size.height, 800, accuracy: 0.001)
    }

    func testHorizontalGrowStopsAtPanelMinimum() {
        let size = MiniPlayerResizeGeometry.contentSize(
            requested: NSSize(width: 600, height: 720),
            current: NSSize(width: 420, height: 720)
        )

        XCTAssertEqual(size.width, 600, accuracy: 0.001)
        XCTAssertEqual(
            size.height - size.width,
            MiniPlayerLayout.minimumDetailHeight,
            accuracy: 0.001
        )
    }

    func testDetailPanelKeepsMinimumHeightDuringVerticalResize() {
        let size = MiniPlayerResizeGeometry.contentSize(
            requested: NSSize(width: 420, height: 430),
            current: NSSize(width: 420, height: 720)
        )

        XCTAssertEqual(size.width, 420, accuracy: 0.001)
        XCTAssertEqual(
            size.height - size.width,
            MiniPlayerLayout.minimumDetailHeight,
            accuracy: 0.001
        )
    }

    func testDiagonalResizeRoutesExtraHeightIntoPanel() {
        let size = MiniPlayerResizeGeometry.contentSize(
            requested: NSSize(width: 500, height: 830),
            current: NSSize(width: 420, height: 720)
        )

        XCTAssertEqual(size.width, 500, accuracy: 0.001)
        XCTAssertEqual(size.height, 830, accuracy: 0.001)
    }

    func testCollapsedTracksWidthOnHorizontalEdgeDrag() {
        let size = MiniPlayerResizeGeometry.collapsedSize(
            requested: NSSize(width: 460, height: 420),
            current: NSSize(width: 420, height: 420)
        )

        XCTAssertEqual(size.width, 460, accuracy: 0.001)
        XCTAssertEqual(size.height, 460, accuracy: 0.001)
    }

    func testCollapsedGrowsViaVerticalEdgeDrag() {
        let size = MiniPlayerResizeGeometry.collapsedSize(
            requested: NSSize(width: 420, height: 450),
            current: NSSize(width: 420, height: 420)
        )

        XCTAssertEqual(size.width, 450, accuracy: 0.001)
        XCTAssertEqual(size.height, 450, accuracy: 0.001)
    }

    func testCollapsedShrinksViaVerticalEdgeDrag() {
        let size = MiniPlayerResizeGeometry.collapsedSize(
            requested: NSSize(width: 420, height: 396),
            current: NSSize(width: 420, height: 420)
        )

        XCTAssertEqual(size.width, 396, accuracy: 0.001)
        XCTAssertEqual(size.height, 396, accuracy: 0.001)
    }

    func testCollapsedKeepsMinimumSide() {
        let size = MiniPlayerResizeGeometry.collapsedSize(
            requested: NSSize(width: 420, height: 200),
            current: NSSize(width: 420, height: 420)
        )

        XCTAssertEqual(size.width, MiniPlayerLayout.minimumCompactSide, accuracy: 0.001)
        XCTAssertEqual(size.height, MiniPlayerLayout.minimumCompactSide, accuracy: 0.001)
    }

    func testCollapsedCornerDragTakesDominantAxis() {
        let size = MiniPlayerResizeGeometry.collapsedSize(
            requested: NSSize(width: 380, height: 470),
            current: NSSize(width: 420, height: 420)
        )

        XCTAssertEqual(size.width, 470, accuracy: 0.001)
        XCTAssertEqual(size.height, 470, accuracy: 0.001)
    }

    func testCollapsedKeepsMaximumSide() {
        let size = MiniPlayerResizeGeometry.collapsedSize(
            requested: NSSize(width: 800, height: 800),
            current: NSSize(width: 420, height: 420)
        )

        XCTAssertEqual(size.width, MiniPlayerLayout.maximumCompactSide, accuracy: 0.001)
        XCTAssertEqual(size.height, MiniPlayerLayout.maximumCompactSide, accuracy: 0.001)
    }

    func testDetailContentWidthClampedToMaximum() {
        let size = MiniPlayerResizeGeometry.contentSize(
            requested: NSSize(width: 750, height: 900),
            current: NSSize(width: 420, height: 720)
        )

        XCTAssertEqual(size.width, MiniPlayerLayout.maximumCompactSide, accuracy: 0.001)
    }

    @MainActor
    func testPanelControllerTracksUserCompactSideOnResize() {
        let controller = MiniPlayerPanelController()
        let panel = NSPanel(
            contentRect: NSRect(x: 100, y: 100, width: 480, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        let size = controller.windowWillResize(panel, to: NSSize(width: 480, height: 480))
        XCTAssertEqual(size.width, 480, accuracy: 0.001)
        XCTAssertEqual(size.height, 480, accuracy: 0.001)
    }

    func testBlurCacheIsStrictlyScopedToCoverArtKey() {
        let cache = MiniPlayerVariableBlurCache.shared
        let size = CGSize(width: 320, height: 320)

        let unknownKey = "non-existent-art-\(UUID().uuidString)"
        XCTAssertNil(cache.cached(coverArt: unknownKey, targetSize: size))

        let keyA = "art-a-\(UUID().uuidString)"
        let dummyImage = NSImage(size: NSSize(width: 320, height: 320))
        dummyImage.lockFocus()
        NSColor.red.drawSwatch(in: NSRect(x: 0, y: 0, width: 320, height: 320))
        dummyImage.unlockFocus()

        let renderedA = cache.renderBlur(coverArt: keyA, source: dummyImage, targetSize: size)
        XCTAssertNotNil(renderedA)
        XCTAssertNotNil(cache.cached(coverArt: keyA, targetSize: size))

        let keyB = "art-b-\(UUID().uuidString)"
        XCTAssertNil(cache.cached(coverArt: keyB, targetSize: size))
    }

    func testRenderBlurAspectFillsNonSquareSource() {
        let cache = MiniPlayerVariableBlurCache.shared
        let targetSize = CGSize(width: 320, height: 320)
        let key = "landscape-art-\(UUID().uuidString)"

        let landscapeImage = NSImage(size: NSSize(width: 800, height: 450))
        landscapeImage.lockFocus()
        NSColor.blue.drawSwatch(in: NSRect(x: 0, y: 0, width: 800, height: 450))
        landscapeImage.unlockFocus()

        let rendered = cache.renderBlur(coverArt: key, source: landscapeImage, targetSize: targetSize)
        let unwrapped = try? XCTUnwrap(rendered)
        XCTAssertNotNil(unwrapped)
        if let size = unwrapped?.size {
            XCTAssertEqual(size.width, 320, accuracy: 0.001)
            XCTAssertEqual(size.height, 320, accuracy: 0.001)
        }
    }

    @MainActor
    func testWindowDidResizeUpdatesUserCompactSideWithoutInLiveResize() {
        let controller = MiniPlayerPanelController()
        let panel = NSPanel(
            contentRect: NSRect(origin: NSPoint(x: 100, y: 100), size: NSSize(width: 480, height: 480)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.delegate = controller
        controller.windowDidResize(Notification(name: NSWindow.didResizeNotification, object: panel))
        XCTAssertEqual(controller.userCompactSide, 480, accuracy: 0.001)
    }
}
