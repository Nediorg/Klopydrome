import XCTest
import AppKit
import SwiftUI
import NavidromeClient
@testable import Klopydrome

/// Pixel-level tests for `KaraokeLine` rendering, driven by `ImageRenderer`
/// exactly like the cover-preset tests. These lock in the visible behavior of
/// a marker-free ACTIVE line: it is always painted in bright `.primary`
/// (Apple Music style) — regressing it to a dim/fill state makes the current
/// line look "fully transparent", which is the bug the fill experiment caused.
@MainActor
final class KaraokeLineRenderTests: XCTestCase {

    /// The active line must be bright the moment it starts (fill experiments
    /// left it dim here, which read as "falls into full transparency").
    func testActiveLineWithoutMarkersIsBrightAtLineStart() {
        let rep = renderLine(text: "Середина строки", lineStart: 10, currentTime: 10)
        XCTAssertNotNil(rep)
        let bright = countBrightPixels(in: rep!)
        XCTAssertGreaterThan(bright, 0, "active line must be bright from its very start")
    }

    /// Mid-line, the active line stays fully bright (no left-to-right sweep).
    func testActiveLineWithoutMarkersIsBrightMidLine() {
        let rep = renderLine(text: "Середина строки", lineStart: 10, currentTime: 15)
        XCTAssertNotNil(rep)
        let bright = countBrightPixels(in: rep!)
        XCTAssertGreaterThan(bright, 0, "active line must be bright while it is being sung")
    }

    /// Non-active lines stay dim: past is light gray, future is darker gray —
    /// never bright white.
    func testNonActiveLinesStayDim() {
        for state in [LyricLineState.past, .future] {
            let rep = renderLine(text: "Середина строки", lineStart: 10, currentTime: 15, state: state)
            XCTAssertNotNil(rep)
            let bright = countBrightPixels(in: rep!)
            XCTAssertEqual(bright, 0, "non-active lines must not render bright white")
        }
    }

    func testWordWhiteFadeSettlesFromWhiteToSungColor() {
        XCTAssertEqual(KaraokeLine.wordSettledOpacity(at: 9.9, wordStart: 10, sungAt: 11), 0.5)
        XCTAssertEqual(KaraokeLine.wordSettledOpacity(at: 10, wordStart: 10, sungAt: 11), 1)
        let middle = KaraokeLine.wordSettledOpacity(at: 10.14, wordStart: 10, sungAt: 11)
        XCTAssertLessThan(middle, 1)
        XCTAssertGreaterThan(middle, 0.85)
        XCTAssertEqual(KaraokeLine.wordSettledOpacity(at: 10.3, wordStart: 10, sungAt: 11), 0.85)
    }

    /// The layout cap must guarantee the worst-case scaled line fits the
    /// padded column exactly.
    func testLineWrapWidthGuaranteesScaledFit() {
        let wrap = LyricsView.lineWrapWidth(viewportWidth: 900, horizontalPadding: 40)
        XCTAssertEqual(wrap * KaraokeLine.maxLineScale, 820, accuracy: 0.001)
        XCTAssertEqual(
            LyricsView.lineWrapWidth(viewportWidth: 10, horizontalPadding: 40),
            0,
            accuracy: 0.001
        )
    }

    /// Regression: on wide panels the active line's center-anchored scale used
    /// to push its glyphs through the leading padding and out of the window.
    /// With the production wrap cap the padding zone must stay empty.
    func testActiveLineStaysInsideLeadingPaddingOnWidePanel() {
        let viewport: CGFloat = 900
        let padding: CGFloat = 40
        let wrap = LyricsView.lineWrapWidth(viewportWidth: viewport, horizontalPadding: padding)
        let phrase = "Никто не знает тебя, и я тоже не знаю себя, где-то между всей землёй и небом "
        let rep = renderPaddedLine(
            text: phrase + phrase + phrase,
            viewportWidth: viewport,
            padding: padding,
            wrapWidth: wrap
        )
        XCTAssertNotNil(rep)
        XCTAssertEqual(countBrightPixels(in: rep!, maxColumn: Int(padding) - 2), 0)
        XCTAssertGreaterThan(countBrightPixels(in: rep!), 0)
    }

    // MARK: Helpers

    private func renderLine(
        text: String,
        lineStart: Double,
        currentTime: Double,
        state: LyricLineState = .now
    ) -> NSBitmapImageRep? {
        let line = KaraokeLine(
            text: text,
            lineStart: lineStart,
            currentTime: currentTime,
            state: state,
            onTap: {}
        )
        let renderer = ImageRenderer(content: AnyView(
            line.frame(width: 400, height: 80).environment(\.colorScheme, .dark)
        ))
        return renderCGImage(renderer: renderer, size: CGSize(width: 400, height: 80))
    }

    /// Mirrors the `LyricsView` embedding: padded column, capped wrap width.
    private func renderPaddedLine(
        text: String,
        viewportWidth: CGFloat,
        padding: CGFloat,
        wrapWidth: CGFloat
    ) -> NSBitmapImageRep? {
        let line = KaraokeLine(
            text: text,
            lineStart: 10,
            currentTime: 10,
            state: .now,
            maxLayoutWidth: wrapWidth,
            onTap: {}
        )
        let size = CGSize(width: viewportWidth, height: 160)
        let renderer = ImageRenderer(content: AnyView(
            line
                .padding(.horizontal, padding)
                .frame(width: viewportWidth, height: 160, alignment: .topLeading)
                .environment(\.colorScheme, .dark)
        ))
        return renderCGImage(renderer: renderer, size: size)
    }

    private func renderCGImage(renderer: ImageRenderer<AnyView>, size: CGSize) -> NSBitmapImageRep? {
        renderer.scale = 1
        renderer.isOpaque = true
        var cgImage: CGImage?
        for _ in 0..<20 {
            cgImage = renderer.cgImage
            if cgImage != nil { break }
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        guard let cgImage else { return nil }
        let nsImage = NSImage(cgImage: cgImage, size: size)
        guard let tiff = nsImage.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)
    }

    private func countBrightPixels(in rep: NSBitmapImageRep) -> Int {
        countBrightPixels(in: rep, maxColumn: rep.pixelsWide)
    }

    private func countBrightPixels(in rep: NSBitmapImageRep, maxColumn: Int) -> Int {
        var count = 0
        for row in stride(from: 0, to: rep.pixelsHigh, by: 2) {
            for column in stride(from: 0, to: min(maxColumn, rep.pixelsWide), by: 2) {
                let color = rep.colorAt(x: column, y: row) ?? .black
                let srgb = color.usingColorSpace(.sRGB) ?? color
                let red = Int((srgb.redComponent * 255).rounded())
                let green = Int((srgb.greenComponent * 255).rounded())
                let blue = Int((srgb.blueComponent * 255).rounded())
                if red > 180 && green > 180 && blue > 180 { count += 1 }
            }
        }
        return count
    }
}
