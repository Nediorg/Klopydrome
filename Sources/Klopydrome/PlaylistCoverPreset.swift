import SwiftUI
import AppKit

/// A gallery swatch the user picks as a playlist cover: a two-stop gradient.
/// Presets with `hasText` overlay the playlist's title in the top-left corner
/// (black, left-aligned, forced two-line wrap) per the Apple Music design
/// system; plain presets stay textless.
struct PlaylistCoverPreset: Identifiable, Hashable {
    let id: String
    /// Short display name for the gallery tooltip (not drawn on the cover).
    let baseName: String
    /// Gradient stops, top-leading to bottom-trailing.
    let top: Color
    let bottom: Color
    /// Whether the cover draws the playlist title as SF Bold top-left.
    var hasText: Bool

    init(id: String, baseName: String, top: Color, bottom: Color, hasText: Bool = false) {
        self.id = id
        self.baseName = baseName
        self.top = top
        self.bottom = bottom
        self.hasText = hasText
    }

    static func == (lhs: PlaylistCoverPreset, rhs: PlaylistCoverPreset) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension PlaylistCoverPreset {
    /// The pre-canned swatches, styled after Apple Music's playlist covers.
    /// Every gradient preset also draws the playlist title in the top-left
    /// corner, so text is available on all of them.
    static let all: [PlaylistCoverPreset] = [
        // Default: white → red (135°), always draws the title. First in the
        // gallery so text is visible out of the box.
        PlaylistCoverPreset(id: "rose_white", baseName: "Роза", top: .white, bottom: Color(red: 1.0, green: 0.22, blue: 0.38), hasText: true),
        PlaylistCoverPreset(id: "ocean", baseName: "Океан", top: Color(red: 0.20, green: 0.45, blue: 0.95), bottom: Color(red: 0.08, green: 0.10, blue: 0.45), hasText: true),
        PlaylistCoverPreset(id: "ember", baseName: "Уголь", top: Color(red: 0.95, green: 0.40, blue: 0.20), bottom: Color(red: 0.45, green: 0.10, blue: 0.10), hasText: true),
        PlaylistCoverPreset(id: "lagoon", baseName: "Лагуна", top: Color(red: 0.20, green: 0.80, blue: 0.65), bottom: Color(red: 0.08, green: 0.35, blue: 0.35), hasText: true),
        PlaylistCoverPreset(id: "orchid", baseName: "Орхидея", top: Color(red: 0.72, green: 0.22, blue: 0.85), bottom: Color(red: 0.30, green: 0.08, blue: 0.50), hasText: true),
        PlaylistCoverPreset(id: "dawn", baseName: "Рассвет", top: Color(red: 0.30, green: 0.70, blue: 0.92), bottom: Color(red: 0.10, green: 0.20, blue: 0.62), hasText: true),
        PlaylistCoverPreset(id: "sorbet", baseName: "Сорбе", top: Color(red: 1.00, green: 0.75, blue: 0.40), bottom: Color(red: 1.00, green: 0.30, blue: 0.45), hasText: true),
        PlaylistCoverPreset(id: "moss", baseName: "Мош", top: Color(red: 0.45, green: 0.75, blue: 0.35), bottom: Color(red: 0.10, green: 0.35, blue: 0.18), hasText: true),
        // Text swatches — variations with stronger dark contrast.
        PlaylistCoverPreset(id: "t_strawberry", baseName: "Strawberry", top: Color(red: 0.98, green: 0.55, blue: 0.55), bottom: Color(red: 0.55, green: 0.10, blue: 0.25), hasText: true),
        PlaylistCoverPreset(id: "t_ocean", baseName: "Ocean Club", top: Color(red: 0.30, green: 0.60, blue: 0.90), bottom: Color(red: 0.10, green: 0.15, blue: 0.40), hasText: true),
        PlaylistCoverPreset(id: "t_void", baseName: "PVC", top: Color(red: 0.35, green: 0.20, blue: 0.60), bottom: Color(red: 0.08, green: 0.05, blue: 0.20), hasText: true),
        PlaylistCoverPreset(id: "t_solar", baseName: "Solar", top: Color(red: 1.00, green: 0.55, blue: 0.15), bottom: Color(red: 0.70, green: 0.15, blue: 0.10), hasText: true),
    ]
}

// MARK: Rendering

extension PlaylistCoverPreset {
    /// Deterministic choice of text colour: white on dark thumb, black on light.
    var textColor: Color {
        averageLuminance > 0.6 ? .black : .white
    }

    /// Weighted average luminance of the gradient stops (0…1).
    var averageLuminance: CGFloat {
        let c = [top, bottom].compactMap { NSColor($0).usingColorSpace(.sRGB) }
        guard !c.isEmpty else { return 0.5 }
        let lum = c.map { $0.luminance }.reduce(0, +) / CGFloat(c.count)
        return lum
    }

    /// The cover drawn at a given point size with the playlist title, ready
    /// for the carousel or `ImageRenderer`.
    func view(size: CGFloat, title: String? = nil) -> some View {
        CoverPresetView(preset: self, size: size, title: title)
    }

    /// Renders the cover as PNG bytes for uploading to the server.
    /// Must be called on the main actor; `ImageRenderer` needs a live context.
    @MainActor
    func pngData(size: CGFloat = 1024, title: String? = nil) -> Data? {
        let renderer = ImageRenderer(content: view(size: size, title: title))
        renderer.scale = 1
        renderer.isOpaque = true
        guard let cg = renderer.cgImage else { return nil }
        return NSImage(cgImage: cg, size: .init(width: size, height: size))
            .pngData()
    }
}

/// The on-screen swatch. `title` is the live playlist name; for text presets
/// an empty title falls back to the «Название плейлиста» placeholder so the
/// cover always shows something once text was expected.
struct CoverPresetView: View {
    let preset: PlaylistCoverPreset
    let size: CGFloat
    let title: String?

    /// What the cover draws when the field is empty on a text preset.
    static let placeholderTitle = "Название плейлиста"

    var body: some View {
        // Explicit frame: ImageRenderer proposes no size, so without it the
        // canvas collapses to the text's intrinsic size.
        ZStack {
            LinearGradient(colors: [preset.top, preset.bottom],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
            if preset.hasText {
                Text(preset.displayText(title: title))
                    .font(.system(size: titleFontSize, weight: .bold, design: .default))
                    .foregroundStyle(preset.textColor)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(titleFontSize * 0.08)
                    .lineLimit(nil)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, size * 0.12)
                    .padding(.horizontal, size * 0.09)
            }
        }
        .frame(width: size, height: size)
    }

    /// Bold headline size: normal, or a single step down once the title gets
    /// long enough that it would otherwise overrun the cover height.
    private var titleFontSize: CGFloat {
        let count = (title ?? "").trimmingCharacters(in: .whitespaces).count
        let base = size * 0.13
        return count > 15 ? base * 0.85 : base
    }
}

extension PlaylistCoverPreset {
    /// The string drawn on the cover: the typed title, or the placeholder when
    /// the field is empty and text was expected.
    func displayText(title: String?) -> String {
        let trimmed = (title ?? "").trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        return hasText ? CoverPresetView.placeholderTitle : ""
    }
}

private extension NSColor {
    /// Perceived luminance (Rec. 709) in 0…1.
    var luminance: CGFloat {
        let c = usingColorSpace(.sRGB) ?? self
        let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
}

extension NSImage {
    func pngData() -> Data? {
        guard let tiff = tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}