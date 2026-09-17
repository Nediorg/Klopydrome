import AppKit
import NavidromeClient
import SwiftUI

/// Caches a transparent full-size image for AppKit hit testing.
///
/// In AppKit, a borderless `NSButton` created by SwiftUI `Menu` calculates its
/// click hit target (`imageRectForBounds:`) strictly from the bounds of the image
/// passed in its label. Passing a transparent `NSImage` of exact canvas size (e.g. 32x32)
/// ensures AppKit allocates a full 32x32 hit area without drawing any visible pixels.
/// The visual glyph (`Image(systemName: "ellipsis")`) and circular background
/// (`Circle()`) are rendered natively in SwiftUI, ensuring optical centering and
/// identical appearance to `RoundFavoriteButton`.
@MainActor
enum EllipsisMenuIcon {
    private static var cache: [Int: NSImage] = [:]

    static func transparentImage(size: CGFloat) -> NSImage {
        let key = Int(size)
        if let cached = cache[key] { return cached }
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in true }
        cache[key] = img
        return img
    }
}

/// Round ellipsis menu button matching RoundFavoriteButton for detail-page action rows.
struct RoundEllipsisMenu<MenuContent: View>: View {
    @ViewBuilder let content: MenuContent
    var size: CGFloat = 32

    @State private var hovering = false

    var body: some View {
        ZStack {
            Circle()
                .fill(hovering ? AMColor.surfaceTertiaryHover : AMColor.surfaceLight)
                .frame(width: size, height: size)

            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(hovering ? Color.primary : Color.secondary)

            // Transparent Menu overlay to capture mouse clicks across the full 32x32 circle
            Menu {
                content
            } label: {
                Image(nsImage: EllipsisMenuIcon.transparentImage(size: size))
                    .frame(width: size, height: size)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .offset(x: 2)
            .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .onHover { hovering = $0 }
        .help("Ещё".localized)
        .accessibilityLabel("Ещё".localized)
    }
}
