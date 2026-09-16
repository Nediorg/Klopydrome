import AppKit
import SwiftUI

/// Apple Music-styled volume slider for the main window toolbar.
///
/// Pure SwiftUI implementation using `DragGesture` for mouse interaction.
/// This avoids the AppKit event-routing issues that occur with NSControl
/// subclasses in the unified-titlebar area, where `NSTitlebarContainerView`
/// hijacks mouseDown events before they reach embedded `NSViewRepresentable`
/// controls. SwiftUI's gesture system runs inside `NSHostingView` and is
/// not affected by titlebar event interception.
///
/// Scroll-wheel support is provided by a thin `NSView` underlay
/// (`ScrollWheelCaptureView`) that forwards scroll events without
/// interfering with drag gestures.
struct ToolbarVolumeSlider: View {
    @Binding var value: Float

    private static let trackHeight: CGFloat = 2.0
    private static let thumbDiameter: CGFloat = 12.0
    private static let ringStrokeWidth: CGFloat = 1.0

    @State private var isHovered = false
    @State private var isDragging = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let thumbRadius = Self.thumbDiameter / 2
            let trackInset = thumbRadius
            let trackWidth = max(0, width - trackInset * 2)
            let progress = CGFloat(min(max(value, 0), 1))
            let thumbCenterX = trackInset + trackWidth * progress

            ZStack {
                // Track segments
                trackSegments(
                    trackInset: trackInset,
                    trackWidth: trackWidth,
                    thumbCenterX: thumbCenterX,
                    thumbRadius: thumbRadius,
                    height: height
                )

                // Thumb ring
                Circle()
                    .strokeBorder(activeGrayColor, lineWidth: Self.ringStrokeWidth)
                    .frame(width: Self.thumbDiameter, height: Self.thumbDiameter)
                    .position(x: thumbCenterX, y: height / 2)
            }
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .overlay {
                InteractiveSliderTrack(
                    onDragStarted: { isDragging = true },
                    onDragChanged: { progress in
                        let newVolume = Float(progress)
                        if abs(newVolume - value) > 0.001 {
                            value = newVolume
                        }
                    },
                    onDragEnded: { progress in
                        isDragging = false
                        let newVolume = Float(progress)
                        if abs(newVolume - value) > 0.001 {
                            value = newVolume
                        }
                    },
                    onHoverChanged: { isHovered = $0 },
                    onScrollWheel: { delta in
                        let newVol = min(max(value + delta, 0), 1)
                        if abs(newVol - value) > 0.001 {
                            value = newVol
                        }
                    },
                    calculateProgress: { point, _ in
                        let clampedX = min(max(point.x - trackInset, 0), trackWidth)
                        return trackWidth > 0 ? clampedX / trackWidth : 0
                    }
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Громкость")
        .accessibilityValue("\(Int(value * 100))%")
        .accessibilityAdjustableAction { direction in
            let delta: Float = direction == .increment ? 0.05 : -0.05
            value = min(max(value + delta, 0), 1)
        }
    }

    private var activeGrayColor: Color {
        if isHovered || isDragging {
            return Color(nsColor: NSColor.secondaryLabelColor.blended(
                withFraction: 0.25, of: .labelColor
            ) ?? NSColor.secondaryLabelColor)
        }
        return Color(nsColor: NSColor.secondaryLabelColor)
    }

    private func trackSegments(
        trackInset: CGFloat,
        trackWidth: CGFloat,
        thumbCenterX: CGFloat,
        thumbRadius: CGFloat,
        height: CGFloat
    ) -> some View {
        let trackHeight = Self.trackHeight
        let trackY = height / 2

        return ZStack {
            // Filled segment (left of thumb)
            let filledEnd = max(trackInset, thumbCenterX - thumbRadius)
            if filledEnd > trackInset {
                RoundedRectangle(cornerRadius: trackHeight / 2)
                    .fill(activeGrayColor)
                    .frame(width: filledEnd - trackInset, height: trackHeight)
                    .position(
                        x: trackInset + (filledEnd - trackInset) / 2,
                        y: trackY
                    )
            }

            // Unfilled segment (right of thumb)
            let unfilledStart = min(trackInset + trackWidth, thumbCenterX + thumbRadius)
            let unfilledEnd = trackInset + trackWidth
            if unfilledEnd > unfilledStart {
                let unfilledAlpha = (isHovered || isDragging) ? 0.18 : 0.12
                RoundedRectangle(cornerRadius: trackHeight / 2)
                    .fill(Color(nsColor: .labelColor).opacity(unfilledAlpha))
                    .frame(width: unfilledEnd - unfilledStart, height: trackHeight)
                    .position(
                        x: unfilledStart + (unfilledEnd - unfilledStart) / 2,
                        y: trackY
                    )
            }
        }
    }
}
