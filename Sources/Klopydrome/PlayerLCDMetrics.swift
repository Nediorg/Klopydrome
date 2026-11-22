import CoreGraphics
import Foundation
import NavidromeClient

enum PlayerLCDMetrics {
    static let lcdHeight: CGFloat = 42
    static let coverWidth: CGFloat = 42
    static let timeHorizontalPadding: CGFloat = 4
    static let timeToSubtitleGap: CGFloat = 5
    static let textHorizontalPadding: CGFloat = 8
    static let actionButtonSide: CGFloat = 18
    static let controlsSpacing: CGFloat = 0
    static let controlsTrailingPadding: CGFloat = 4
    static let titleToControlsGap: CGFloat = 4
    static let defaultElapsedWidth: CGFloat = 20
    static let defaultRemainingWidth: CGFloat = 25
    static let marqueeSpeed: CGFloat = 30
    static let marqueeStartDelay: TimeInterval = 3.0
    static let marqueeEndPause: TimeInterval = 1.5
    static let marqueeStartPause: TimeInterval = 3.0
    static let marqueeEdgeFadeWidth: CGFloat = 8

    struct HorizontalLane: Equatable {
        let minLeading: CGFloat
        let minTrailing: CGFloat
    }

    struct TextPlacement: Equatable {
        let leadingOffset: CGFloat
        let availableWidth: CGFloat
        let isOverflowing: Bool
    }

    static var unhoveredControlsWidth: CGFloat {
        actionButtonSide + controlsTrailingPadding
    }

    static var hoveredControlsWidth: CGFloat {
        actionButtonSide * 2 + controlsSpacing + controlsTrailingPadding
    }

    static func titleLane(isHovered: Bool) -> HorizontalLane {
        let controlsWidth = isHovered ? hoveredControlsWidth : unhoveredControlsWidth
        return HorizontalLane(
            minLeading: coverWidth + textHorizontalPadding,
            minTrailing: controlsWidth + titleToControlsGap
        )
    }

    static func subtitleLane(
        isHovered: Bool,
        elapsedWidth: CGFloat,
        remainingWidth: CGFloat
    ) -> HorizontalLane {
        guard isHovered else {
            return HorizontalLane(
                minLeading: coverWidth + textHorizontalPadding,
                minTrailing: textHorizontalPadding
            )
        }
        let elapsed = elapsedWidth > 0 ? elapsedWidth : defaultElapsedWidth
        let remaining = remainingWidth > 0 ? remainingWidth : defaultRemainingWidth
        return HorizontalLane(
            minLeading: coverWidth + timeHorizontalPadding + elapsed + timeToSubtitleGap,
            minTrailing: timeHorizontalPadding + remaining + timeToSubtitleGap
        )
    }

    static func placement(
        lcdWidth: CGFloat,
        textWidth: CGFloat,
        lane: HorizontalLane
    ) -> TextPlacement {
        let available = max(0, lcdWidth - lane.minLeading - lane.minTrailing)
        guard lcdWidth > 0, textWidth > 0 else {
            return TextPlacement(leadingOffset: lane.minLeading, availableWidth: available, isOverflowing: false)
        }
        if textWidth > available + 1 {
            return TextPlacement(leadingOffset: lane.minLeading, availableWidth: available, isOverflowing: true)
        }
        let centered = (lcdWidth - textWidth) / 2
        let maxLeading = max(lane.minLeading, lcdWidth - lane.minTrailing - textWidth)
        let leading = min(max(centered, lane.minLeading), maxLeading)
        return TextPlacement(leadingOffset: leading, availableWidth: available, isOverflowing: false)
    }

    static func marqueeDistance(textWidth: CGFloat, availableWidth: CGFloat) -> CGFloat {
        guard textWidth > availableWidth + 1 else { return 0 }
        return textWidth - availableWidth
    }

    static func marqueeLegDuration(distance: CGFloat) -> TimeInterval {
        guard distance > 0 else { return 0 }
        return max(1.0, TimeInterval(distance / marqueeSpeed))
    }

    static func marqueeOffset(elapsed: TimeInterval, distance: CGFloat) -> CGFloat {
        guard elapsed > 0, distance > 0 else { return 0 }
        let leg = marqueeLegDuration(distance: distance)
        let forwardEnd = leg
        let holdRightEnd = forwardEnd + marqueeEndPause
        let returnEnd = holdRightEnd + leg
        let cyclePeriod = returnEnd + marqueeStartPause
        let phase = elapsed.truncatingRemainder(dividingBy: cyclePeriod)

        if phase < forwardEnd {
            return CGFloat(phase / leg) * distance
        } else if phase < holdRightEnd {
            return distance
        } else if phase < returnEnd {
            return CGFloat(1 - (phase - holdRightEnd) / leg) * distance
        } else {
            return 0
        }
    }
}
