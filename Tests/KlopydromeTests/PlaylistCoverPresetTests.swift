import XCTest
import AppKit
import SwiftUI
import NavidromeClient
@testable import Klopydrome

/// Renders the preset covers the same way the app does and asserts the output
/// matches the intended Apple-Music-style design: exact requested size,
/// top-leading→bottom-trailing gradient, and a drawn title in the top-left
/// for text presets.
final class PlaylistCoverPresetTests: XCTestCase {

    private let rose = PlaylistCoverPreset(
        id: "rose", baseName: "Роза",
        top: .white, bottom: Color(red: 1.0, green: 0.22, blue: 0.38),
        hasText: true
    )

    // MARK: Resolution

    @MainActor
    func testRendersAtRequestedPixelSize() {
        XCTAssertEqual(renderPNG(preset: rose, size: 1024, title: "Рок")?.pixelsWide, 1024)
        XCTAssertEqual(renderPNG(preset: rose, size: 1024, title: "Рок")?.pixelsHigh, 1024)
    }

    @MainActor
    func testRendersCarouselSize() {
        let rep = renderPNG(preset: rose, size: 126, title: "Рок")
        XCTAssertEqual(rep?.pixelsWide, 126)
        XCTAssertEqual(rep?.pixelsHigh, 126)
    }

    @MainActor
    func testPngDataMatchesRenderedBitmap() {
        let data = rose.pngData(size: 512, title: "Рок")
        let rep = data.flatMap { NSBitmapImageRep(data: $0) }
        XCTAssertNotNil(rep, "pngData should return decodable PNG bytes")
        XCTAssertEqual(rep?.pixelsWide, 512)
        XCTAssertEqual(rep?.pixelsHigh, 512)
    }

    // MARK: Gradient

    @MainActor
    func testGradientTopLeadingIsLight() {
        let rep = renderPNG(preset: rose, size: 512, title: "Рок")
        let c = tryColor(rep!, x: 4, y: 4)
        XCTAssertGreaterThan(c.r, 200)
        XCTAssertGreaterThan(c.g, 200)
        XCTAssertGreaterThan(c.b, 200)
    }

    @MainActor
    func testGradientBottomTrailingIsRed() {
        let rep = renderPNG(preset: rose, size: 512, title: "Рок")
        let c = tryColor(rep!, x: 507, y: 507)
        XCTAssertGreaterThan(c.r, 200, "bottom-trailing should be strongly red")
        XCTAssertLessThan(c.g, 120)
        XCTAssertLessThan(c.b, 150)
    }

    @MainActor
    func testGradientDarkensTowardBottomTrailing() {
        let rep = renderPNG(preset: rose, size: 512, title: "Рок")
        let tl = tryColor(rep!, x: 4, y: 4)
        let br = tryColor(rep!, x: 507, y: 507)
        XCTAssertLessThan(br.g + br.b, tl.g + tl.b)
    }

    // MARK: Text

    @MainActor
    func testTitleIsDrawnTopLeft() {
        let rep = renderPNG(preset: rose, size: 512, title: "Рок")
        XCTAssertGreaterThan(darkTextIn(rep: rep!, y: 30...220), 0, "text preset should draw the title in the top-left band")
    }

    @MainActor
    func testEmptyTitleFallsBackToPlaceholder() {
        let rep = renderPNG(preset: rose, size: 512, title: "")
        XCTAssertGreaterThan(darkTextIn(rep: rep!, y: 30...220), 0, "empty title on a text preset should draw the placeholder")
    }

    @MainActor
    func testPlainPresetWithoutTextStaysTextless() {
        let plain = PlaylistCoverPreset(id: "plain", baseName: "Plain", top: .white, bottom: .blue, hasText: false)
        let rep = renderPNG(preset: plain, size: 512, title: "Любой заголовок")
        XCTAssertEqual(darkTextIn(rep: rep!, y: 0...220), 0, "hasText=false must not draw anything")
    }

    // MARK: Helpers

    @MainActor
    private func renderPNG(preset: PlaylistCoverPreset, size: CGFloat, title: String?) -> NSBitmapImageRep? {
        let renderer = ImageRenderer(content: AnyView(preset.view(size: size, title: title)))
        renderer.scale = 1
        renderer.isOpaque = true
        var cg: CGImage?
        for _ in 0..<20 {
            cg = renderer.cgImage
            if cg != nil { break }
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        guard let cg else { return nil }
        let ns = NSImage(cgImage: cg, size: .init(width: size, height: size))
        guard let tiff = ns.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)
    }

    @MainActor
    private func tryColor(_ rep: NSBitmapImageRep, x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
        let c = rep.colorAt(x: x, y: y) ?? .black
        let s = c.usingColorSpace(.sRGB) ?? c
        return (Int((s.redComponent * 255).rounded()),
                Int((s.greenComponent * 255).rounded()),
                Int((s.blueComponent * 255).rounded()))
    }

    @MainActor
    private func darkTextIn(rep: NSBitmapImageRep, y range: ClosedRange<Int>) -> Int {
        var count = 0
        let w = rep.pixelsWide
        for y in stride(from: range.lowerBound, to: max(range.upperBound, range.lowerBound + 1), by: 2) {
            for x in stride(from: 0, to: w, by: 2) {
                let c = tryColor(rep, x: x, y: y)
                if c.r < 100 && c.g < 100 && c.b < 100 { count += 1 }
            }
        }
        return count
    }

    @MainActor
    func testModalCarouselCentersSlot1ByDefault() {
        let app = AppState()
        let modal = CreatePlaylistModal(songs: [])
            .environment(app)
        let hosting = NSHostingView(rootView: modal)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 800),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        hosting.layoutSubtreeIfNeeded()

        for _ in 0..<10 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }

        func findCarouselScrollView(in view: NSView) -> NSScrollView? {
            if let scrollView = view as? NSScrollView, scrollView.frame.width == 370 {
                return scrollView
            }
            for sub in view.subviews {
                if let found = findCarouselScrollView(in: sub) { return found }
            }
            return nil
        }

        guard let scrollView = findCarouselScrollView(in: hosting) else {
            XCTFail("Carousel NSScrollView not found")
            return
        }

        let originX = scrollView.contentView.bounds.origin.x
        let screenX = 174.0 - originX
        XCTAssertEqual(screenX, 105.0, accuracy: 1.0, "Slot 1 must be centered with 105pt horizontal margin")
    }

    @MainActor
    func testModalCarouselCentersSlot0WhenEditingCoverArt() {
        let app = AppState()
        let existing = PlaylistSummary(
            id: "1", name: "Test", comment: nil, owner: nil, coverArt: "art",
            songCount: nil, duration: nil, created: nil, changed: nil,
            isPublic: nil, isReadonly: nil, validUntil: nil
        )
        let modal = CreatePlaylistModal(songs: [], existing: existing)
            .environment(app)
        let hosting = NSHostingView(rootView: modal)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 800),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        hosting.layoutSubtreeIfNeeded()

        for _ in 0..<10 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }

        func findCarouselScrollView(in view: NSView) -> NSScrollView? {
            if let scrollView = view as? NSScrollView, scrollView.frame.width == 370 {
                return scrollView
            }
            for sub in view.subviews {
                if let found = findCarouselScrollView(in: sub) { return found }
            }
            return nil
        }

        guard let scrollView = findCarouselScrollView(in: hosting) else {
            XCTFail("Carousel NSScrollView not found")
            return
        }

        let originX = scrollView.contentView.bounds.origin.x
        let screenX = 0.0 - originX
        XCTAssertEqual(screenX, 105.0, accuracy: 1.0, "Slot 0 must be centered with 105pt horizontal margin")
    }
}