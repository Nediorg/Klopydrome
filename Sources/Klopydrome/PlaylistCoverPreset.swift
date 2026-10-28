import SwiftUI
import AppKit

struct PlaylistCoverPreset: Identifiable, Hashable {
    let id: String
    let baseName: String
    let top: Color
    let bottom: Color
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
    static let all: [PlaylistCoverPreset] = [
        PlaylistCoverPreset(
            id: "rose_white", baseName: "Rose",
            top: .white,
            bottom: Color(red: 1.0, green: 0.22, blue: 0.38),
            hasText: true
        ),
        PlaylistCoverPreset(
            id: "ocean", baseName: "Ocean",
            top: Color(red: 0.20, green: 0.45, blue: 0.95),
            bottom: Color(red: 0.08, green: 0.10, blue: 0.45),
            hasText: true
        ),
        PlaylistCoverPreset(
            id: "ember", baseName: "Ember",
            top: Color(red: 0.95, green: 0.40, blue: 0.20),
            bottom: Color(red: 0.45, green: 0.10, blue: 0.10),
            hasText: true
        ),
        PlaylistCoverPreset(
            id: "lagoon", baseName: "Lagoon",
            top: Color(red: 0.20, green: 0.80, blue: 0.65),
            bottom: Color(red: 0.08, green: 0.35, blue: 0.35),
            hasText: true
        ),
        PlaylistCoverPreset(
            id: "orchid", baseName: "Orchid",
            top: Color(red: 0.72, green: 0.22, blue: 0.85),
            bottom: Color(red: 0.30, green: 0.08, blue: 0.50),
            hasText: true
        ),
        PlaylistCoverPreset(
            id: "dawn", baseName: "Dawn",
            top: Color(red: 0.30, green: 0.70, blue: 0.92),
            bottom: Color(red: 0.10, green: 0.20, blue: 0.62),
            hasText: true
        ),
        PlaylistCoverPreset(
            id: "sorbet", baseName: "Sorbet",
            top: Color(red: 1.00, green: 0.75, blue: 0.40),
            bottom: Color(red: 1.00, green: 0.30, blue: 0.45),
            hasText: true
        ),
        PlaylistCoverPreset(
            id: "moss", baseName: "Moss",
            top: Color(red: 0.45, green: 0.75, blue: 0.35),
            bottom: Color(red: 0.10, green: 0.35, blue: 0.18),
            hasText: true
        ),
        PlaylistCoverPreset(
            id: "t_strawberry", baseName: "Strawberry",
            top: Color(red: 0.98, green: 0.55, blue: 0.55),
            bottom: Color(red: 0.55, green: 0.10, blue: 0.25),
            hasText: true
        ),
        PlaylistCoverPreset(
            id: "t_ocean", baseName: "Ocean Club",
            top: Color(red: 0.30, green: 0.60, blue: 0.90),
            bottom: Color(red: 0.10, green: 0.15, blue: 0.40),
            hasText: true
        ),
        PlaylistCoverPreset(
            id: "t_void", baseName: "PVC",
            top: Color(red: 0.35, green: 0.20, blue: 0.60),
            bottom: Color(red: 0.08, green: 0.05, blue: 0.20),
            hasText: true
        ),
        PlaylistCoverPreset(
            id: "t_solar", baseName: "Solar",
            top: Color(red: 1.00, green: 0.55, blue: 0.15),
            bottom: Color(red: 0.70, green: 0.15, blue: 0.10),
            hasText: true
        )
    ]

    static func preset(for playlistID: String) -> PlaylistCoverPreset {
        let presets = all
        let index = abs(playlistID.hashValue) % presets.count
        return presets[index]
    }
}

extension PlaylistCoverPreset {
    var textColor: Color {
        averageLuminance > 0.6 ? .black : .white
    }

    var averageLuminance: CGFloat {
        let c = [top, bottom].compactMap { NSColor($0).usingColorSpace(.sRGB) }
        guard !c.isEmpty else { return 0.5 }
        let lum = c.map { $0.luminance }.reduce(0, +) / CGFloat(c.count)
        return lum
    }

    func view(size: CGFloat, title: String? = nil) -> some View {
        CoverPresetView(preset: self, size: size, title: title)
    }

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

struct CoverPresetView: View {
    let preset: PlaylistCoverPreset
    let size: CGFloat
    let title: String?

    static let placeholderTitle = "Playlist Name".localized

    var body: some View {
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

    private var titleFontSize: CGFloat {
        let count = (title ?? "").trimmingCharacters(in: .whitespaces).count
        let base = size * 0.13
        return count > 15 ? base * 0.85 : base
    }
}

extension PlaylistCoverPreset {
    func displayText(title: String?) -> String {
        let trimmed = (title ?? "").trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        return hasText ? CoverPresetView.placeholderTitle : ""
    }
}

private extension NSColor {
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

    func squareCropped() -> NSImage {
        if let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let width = cgImage.width
            let height = cgImage.height
            if width > 0, height > 0 {
                let side = min(width, height)
                let cropX = (width - side) / 2
                let cropY = (height - side) / 2
                let cropRect = CGRect(x: cropX, y: cropY, width: side, height: side)
                if let croppedCG = cgImage.cropping(to: cropRect) {
                    return NSImage(cgImage: croppedCG, size: NSSize(width: side, height: side))
                }
            }
        }
        let originalSize = self.size
        guard originalSize.width > 0, originalSize.height > 0 else { return self }
        let side = min(originalSize.width, originalSize.height)
        let cropX = (originalSize.width - side) / 2
        let cropY = (originalSize.height - side) / 2
        let cropRect = NSRect(x: cropX, y: cropY, width: side, height: side)
        let targetSize = NSSize(width: side, height: side)
        let cropped = NSImage(size: targetSize)
        cropped.lockFocus()
        self.draw(in: NSRect(origin: .zero, size: targetSize), from: cropRect, operation: .copy, fraction: 1.0)
        cropped.unlockFocus()
        return cropped
    }
}