import SwiftUI
import AppKit

/// Apple Music-matching color palette from DESIGN_GUIDE.md.
/// Every color is adaptive (light/dark) so the app honours the system
/// appearance instead of forcing a fixed theme.
enum AMColor {
    /// Window / content background
    static let background = adaptive(light: 0xF5F5F7, dark: 0x1C1C1E)
    /// Selected-row highlight in the sidebar: a light neutral, not the accent.
    static let sidebarSelection = adaptive(light: 0xDCDCE2, dark: 0x3A3A3E)
    /// Secondary surfaces: player bar, result cards
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x2C2C2E)
    /// Raised surfaces: search field, active segment, now-playing capsule
    static let surfaceLight = adaptive(light: 0xEBEBEF, dark: 0x3A3A3C)
    /// Slider tracks
    static let trackFill = adaptive(light: 0xD1D1D6, dark: 0x4A4A4C)
    /// Hairline dividers.
    static let divider = adaptive(light: 0xE2E2E6, dark: 0x38383A, alpha: 0.4)
    /// Primary accent — the system accent color.
    static let accent = Color.accentColor
    /// Secondary text.
    static let secondaryText = adaptive(light: 0x6C6C70, dark: 0x98989D)
    /// Tertiary text.
    static let tertiaryText = adaptive(light: 0x8E8E93, dark: 0x6E6E73)
    /// Primary text (titles, names).
    static let primaryText = adaptive(light: 0x1C1C1E, dark: 0xF5F5F7)
    /// Tertiary hover surface for round icon buttons.
    static let surfaceTertiaryHover = adaptive(light: 0xD1D1D6, dark: 0x48484A)
    /// iTunes Store accent (violet).
    static let storeAccent = Color(red: 175/255, green: 82/255, blue: 222/255)
    /// Sidebar background base (under vibrancy).
    static let sidebarBackground = adaptive(light: 0xF5F5F7, dark: 0x202022)
    /// Promo banner red
    static let promo = adaptive(light: 0xE0364E, dark: 0xE8364E)
    /// Player bar below the traffic lights / above content: slightly darker than
    /// the content background so the bar reads as a distinct surface.
    static let playerBar = adaptive(light: 0xEFEFF1, dark: 0x161618)
    /// Right-hand inspector column (lyrics/queue): shares the player-bar surface
    /// so the bar and panel feel connected.
    static let inspector = AMColor.playerBar

    /// Build a dynamic Color from a UIKit/AppKit named color so it flips with
    /// the system light/dark appearance automatically.
    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? NSColor(rgb: dark) : NSColor(rgb: light)
        })
    }
    private static func adaptive(light: UInt32, dark: UInt32, alpha: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return (isDark ? NSColor(rgb: dark) : NSColor(rgb: light)).withAlphaComponent(alpha)
        })
    }
}

/// Semantic text styles mirroring the Apple Music type scale. Prefer these
/// over fixed `.system(size:)` literals so the UI honours Dynamic Type.
enum AMFont {
    static let largeTitle = Font.largeTitle.weight(.bold)
    static let title2 = Font.title2.weight(.regular)
    static let headline = Font.headline
    static let body = Font.body
    static let subheadline = Font.subheadline
    static let caption = Font.caption
    static let footnote = Font.footnote
}

/// Fixed layout metrics shared across the window regions.
enum LayoutMetrics {
    static let playerBarMinWidth: CGFloat = 320
    static let playerBarMaxFraction: CGFloat = 0.32
    static let playerBarMaxWidth: CGFloat = 420
    static let toolbarMinWidth: CGFloat = 750
    static let topTrailingSlotWidth: CGFloat = 48
    static let toolbarLeadingMinWidth: CGFloat = 208
    static let toolbarTrailingMinWidth: CGFloat = 199
    static let trafficLightInset: CGFloat = 28
    static let sidebarMinWidth: CGFloat = 200
    static let sidebarIdealWidth: CGFloat = 220
    static let sidebarMaxWidth: CGFloat = 300
    static let detailColumnMinWidth: CGFloat = 750
    static let inspectorMinWidth: CGFloat = 320
    static let inspectorIdealWidth: CGFloat = 360
    static let windowMinWidth: CGFloat = 1000
    static let miniPlayerMinWidth: CGFloat = 800
}

private extension NSColor {
    /// Creates an sRGB color from a 0xRRGGBB hex.
    convenience init(rgb hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }
}