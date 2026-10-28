import SwiftUI
import AppKit

enum AMColor {
    static let background = adaptive(light: 0xF5F5F7, dark: 0x1C1C1E)
    static let sidebarSelection = adaptive(light: 0xDCDCE2, dark: 0x3A3A3E)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x2C2C2E)
    static let surfaceLight = adaptive(light: 0xEBEBEF, dark: 0x3A3A3C)
    static let trackFill = adaptive(light: 0xD1D1D6, dark: 0x4A4A4C)
    static let divider = adaptive(light: 0xE2E2E6, dark: 0x38383A, alpha: 0.4)
    static let accent = Color.accentColor
    static let secondaryText = adaptive(light: 0x6C6C70, dark: 0x98989D)
    static let tertiaryText = adaptive(light: 0x8E8E93, dark: 0x6E6E73)
    static let primaryText = adaptive(light: 0x1C1C1E, dark: 0xF5F5F7)
    static let surfaceTertiaryHover = adaptive(light: 0xD1D1D6, dark: 0x48484A)
    static let storeAccent = Color(red: 175/255, green: 82/255, blue: 222/255)
    static let sidebarBackground = adaptive(light: 0xF5F5F7, dark: 0x202022)
    static let promo = adaptive(light: 0xE0364E, dark: 0xE8364E)
    static let playerBar = adaptive(light: 0xEFEFF1, dark: 0x161618)
    static let inspector = AMColor.playerBar

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

enum AMFont {
    static let largeTitle = Font.largeTitle.weight(.bold)
    static let title2 = Font.title2.weight(.regular)
    static let headline = Font.headline
    static let body = Font.body
    static let subheadline = Font.subheadline
    static let caption = Font.caption
    static let footnote = Font.footnote

    static let rowTitle = Font.callout.weight(.medium)
    static let rowSubtitle = Font.callout.weight(.regular)
    static let cardTitle = Font.callout.weight(.regular)
    static let cardSubtitle = Font.callout.weight(.regular)
    static let miniTitle = Font.system(size: 12, weight: .medium)
    static let miniSubtitle = Font.system(size: 12, weight: .regular)
    static let actionPill = Font.system(size: 14, weight: .semibold)
    static let actionPillIcon = Font.system(size: 13, weight: .semibold)
}

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
    convenience init(rgb hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }
}