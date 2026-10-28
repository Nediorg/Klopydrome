import AppKit
import Foundation

enum MiniPlayerResizeGeometry {
    static var lastDebugLine = ""

    static func contentSize(requested: NSSize, current: NSSize) -> NSSize {
        let side = min(
            max(MiniPlayerLayout.minimumCompactSide, requested.width),
            MiniPlayerLayout.maximumCompactSide
        )
        let widthChanged = abs(requested.width - current.width) > 0.5
        let heightChanged = abs(requested.height - current.height) > 0.5
        if widthChanged && !heightChanged {
            let height = max(side + MiniPlayerLayout.minimumDetailHeight, current.height)
            return NSSize(width: side, height: height)
        }
        let detailHeight = max(MiniPlayerLayout.minimumDetailHeight, requested.height - side)
        return NSSize(width: side, height: side + detailHeight)
    }

    static func collapsedSize(requested: NSSize, current: NSSize) -> NSSize {
        let widthChanged = abs(requested.width - current.width) > 0.5
        let heightChanged = abs(requested.height - current.height) > 0.5
        let side: CGFloat
        if widthChanged && !heightChanged {
            side = requested.width
        } else if heightChanged && !widthChanged {
            side = requested.height
        } else {
            side = max(requested.width, requested.height)
        }
        let clamped = min(
            max(MiniPlayerLayout.minimumCompactSide, side),
            MiniPlayerLayout.maximumCompactSide
        )
        return NSSize(width: clamped, height: clamped)
    }
}

enum MiniPlayerLayout {
    static let compactSide: CGFloat = 420
    static let minimumCompactSide: CGFloat = 320
    static let maximumCompactSide: CGFloat = 600
    static let panelHeight: CGFloat = 300
    static let minimumDetailHeight: CGFloat = 180
    static let panelAnimationDuration: TimeInterval = 0.22
    static let topMenuEdgeInset: CGFloat = 7
    static let topMenuTrailingInset: CGFloat = 3.5
}
