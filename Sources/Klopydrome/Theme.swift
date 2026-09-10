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
    /// Hairline dividers. Spec dark #38383A @ ~40% opacity (HIG_COMPLIANCE §1.1).
    static let divider = adaptive(light: 0xE2E2E6, dark: 0x38383A, alpha: 0.4)
    /// Primary accent — the system accent color (System Settings → Appearance →
    /// Accent color / Highlight color, Multicolor on Tahoe). Previously a
    /// custom Apple Music red wired via `AccentColor` in the asset catalog +
    /// `NSAccentColorName` / `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME`;
    /// the custom asset has been removed so every tint, sidebar selection and
    /// highlighted icon follows the OS choice automatically.
    static let accent = Color.accentColor
    /// Secondary text. Spec dark #98989D (HIG_COMPLIANCE §1.1).
    static let secondaryText = adaptive(light: 0x6C6C70, dark: 0x98989D)
    /// Tertiary text. Spec dark #6E6E73 — note: darker than secondary (HIG §1.1).
    static let tertiaryText = adaptive(light: 0x8E8E93, dark: 0x6E6E73)
    /// Primary text (titles, names). Spec dark #F5F5F7 (HIG §1.1).
    static let primaryText = adaptive(light: 0x1C1C1E, dark: 0xF5F5F7)
    /// Tertiary hover surface for round icon buttons. Spec dark #48484A (HIG §1.3).
    static let surfaceTertiaryHover = adaptive(light: 0xD1D1D6, dark: 0x48484A)
    /// iTunes Store accent (violet). Spec #AF52DE (HIG §1.1, §3.2).
    static let storeAccent = Color(red: 175/255, green: 82/255, blue: 222/255)
    /// Sidebar background base (under vibrancy). Spec dark #202022 (HIG §1.1, §3.4).
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

/// Semantic text styles mirroring the Apple Music type scale (§1.2 of
/// HIG_COMPLIANCE.md). Prefer these over fixed `.system(size:)` literals so the
/// UI honours Dynamic Type.
enum AMFont {
    static let largeTitle = Font.largeTitle.weight(.bold)
    static let title2 = Font.title2.weight(.regular)
    static let headline = Font.headline
    static let body = Font.body
    static let subheadline = Font.subheadline
    static let caption = Font.caption
    static let footnote = Font.footnote
}

/// Fixed layout metrics shared across the window regions so the sidebar and
/// inspector column stay consistent at any window size.
enum LayoutMetrics {
    /// Minimum width of the now-playing block (downloads icon + LCD) in the
    /// player toolbar. The LCD is the flexible centered `.principal` element,
    /// so this is roughly the narrowest the transport+LCD+volume chain can be
    /// before it must compress. 344 = ~310pt of PlayerLCDView + the 26pt
    /// downloads icon + 8pt gap; 310 keeps the cover, two text lines and the
    /// star/ellipsis slot readable at the narrowest window (see `toolbarMinWidth`)
    /// so no item is pushed into the overflow menu.
    static let playerBarMinWidth: CGFloat = 344
    /// Maximum width for the LCD block: fraction of the toolbar width. Used as
    /// the `idealWidth` of the `.principal` toolbar item, so the LCD actually
    /// grows with the window (a bare `frame(minWidth:maxWidth:)` without
    /// `idealWidth` would stay pinned to its minimum — NSToolbar asks for the
    /// item's ideal size, not the available space).
    static let playerBarMaxFraction: CGFloat = 0.35
    /// Hard ceiling for the LCD block width so it never grows unbounded on very
    /// wide windows even though the fraction would allow more.
    static let playerBarMaxWidth: CGFloat = 400
    /// The toolbar's total minimum budget: leading (152) + principal (344) +
    /// trailing (200) plus the traffic-light inset (~70) and edge margins. It
    /// is used to derive the window floor:
    /// `windowMinWidth = toolbarMinWidth + sidebarMaxWidth` (800 + 300 = 1100).
    /// 800 is padded above the summed item widths: the sidebar (300) also
    /// needs room at the narrowest window, and NSToolbar sizes against the
    /// content area (`window − sidebar`), so the sidebar must be counted at
    /// its maximum, not its minimum.
    static let toolbarMinWidth: CGFloat = 800
    /// Reserved width for the star + ellipsis trailing controls embedded in the
    /// LCD, so song/album text truncates before them rather than being overlaid.
    static let topTrailingSlotWidth: CGFloat = 48
    /// Minimum width of the leading toolbar group (back + transport row ≈ 212
    /// with the back button). Floors like this stop NSToolbar from COMPRESSING
    /// a group's members when the window is at its narrowest — the group keeps
    /// its natural size and overflows into the chevron as a whole instead of
    /// collapsing buttons (paired with `.fixedSize(horizontal:)` in MainView).
    /// 152 is the always-present transport row; the back button (32) adds on
    /// top when it is shown.
    static let toolbarLeadingMinWidth: CGFloat = 152
    /// Minimum width of the trailing toolbar group (volume slider + lyrics/
    /// queue buttons ≈ 200). Same rationale as `toolbarLeadingMinWidth`: the
    /// slider and the 36pt buttons never shrink below their hit targets.
    static let toolbarTrailingMinWidth: CGFloat = 200
    /// Vertical padding under the traffic lights that the sidebar needs to
    /// keep the first row from sitting under them.
    static let trafficLightInset: CGFloat = 28
    /// Minimum width of the sidebar column (see `SidebarView`).
    static let sidebarMinWidth: CGFloat = 200
    /// Ideal resting width of the sidebar column.
    static let sidebarIdealWidth: CGFloat = 220
    /// Maximum width of the sidebar column (see `SidebarView`). The main
    /// window floor reserves the toolbar capacity required at this width.
    static let sidebarMaxWidth: CGFloat = 300
    /// Minimum width of the DETAIL column. The sidebar already has its own
    /// 200–300 cap, but the detail column had no floor: once the divider
    /// reaches the sidebar's maximum, a further drag squeezes the detail to a
    /// sliver (or, once the sidebar hits its min, drags the whole window below
    /// the toolbar floor via the split-divider→window-resize path). 480 keeps
    /// grids/tables usable; summed with the sidebar min (200) it totals 680,
    /// comfortably under `windowMinWidth`.
    static let detailColumnMinWidth: CGFloat = 480
    /// Inspector column sizing.
    static let inspectorMinWidth: CGFloat = 320
    static let inspectorIdealWidth: CGFloat = 360
    /// Narrowest usable window width. Derived from the layout budget:
    /// `toolbarMinWidth` (800) + `sidebarMaxWidth` (300) = 1100. The sidebar
    /// must be counted at its MAXIMUM, not its minimum: NSToolbar in a
    /// `NavigationSplitView` sizes against the content area, so the toolbar
    /// only ever sees `window − sidebar`. With a wide sidebar the toolbar
    /// budget would silently shrink below its floor and fold items into the
    /// overflow chevron. Below this value NSToolbar has no API to disable the
    /// chevron, so the window must never be resizable narrower. Enforced both
    /// via `.frame(minWidth:)` and, at the AppKit level, via
    /// `window.contentMinSize` + `window.minSize` (see `configureWindowToolbar`).
    static let windowMinWidth: CGFloat = LayoutMetrics.toolbarMinWidth + LayoutMetrics.sidebarMaxWidth
    /// The mini-player window has no window-toolbar items, so its minimum is
    /// only the content (artwork + inspector column + padding), independent of
    /// `windowMinWidth`'s toolbar math.
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