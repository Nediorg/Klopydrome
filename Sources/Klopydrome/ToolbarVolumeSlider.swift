import AppKit
import SwiftUI

/// Apple Music-styled volume slider for the main window toolbar.
///
/// Implemented via AppKit `NSControl` to guarantee `mouseDownCanMoveWindow = false`,
/// completely preventing the window from dragging when clicking or sliding the volume,
/// and supporting scroll-wheel volume adjustments.
struct ToolbarVolumeSlider: NSViewRepresentable {
    @Binding var value: Float

    func makeNSView(context: Context) -> VolumeSliderNSView {
        let view = VolumeSliderNSView()
        view.value = value
        view.onValueChanged = { newValue in
            DispatchQueue.main.async {
                if abs(value - newValue) > 0.001 {
                    value = newValue
                }
            }
        }
        return view
    }

    func updateNSView(_ nsView: VolumeSliderNSView, context: Context) {
        if abs(nsView.value - value) > 0.001 {
            nsView.value = value
        }
    }
}

final class VolumeSliderNSView: NSControl {
    private static let trackHeight: CGFloat = 2.0
    private static let thumbDiameter: CGFloat = 12.0
    private static let ringStrokeWidth: CGFloat = 1.0
    private static var thumbRadius: CGFloat { thumbDiameter / 2 }

    var value: Float = 1.0 {
        didSet {
            let clamped = min(max(value, 0), 1)
            if abs(currentDrawnValue - clamped) > 0.001 {
                currentDrawnValue = clamped
                needsDisplay = true
            }
        }
    }
    var onValueChanged: ((Float) -> Void)?

    private var currentDrawnValue: Float = 1.0
    private var isDragging = false
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        postsFrameChangedNotifications = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        postsFrameChangedNotifications = true
    }

    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        self.trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        window?.makeFirstResponder(self)
        isDragging = true
        updateVolume(from: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        updateVolume(from: event)
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            isDragging = false
            updateVolume(from: event)
            needsDisplay = true
        }
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = Float(event.scrollingDeltaY + event.scrollingDeltaX * 0.5)
        let multiplier: Float = event.hasPreciseScrollingDeltas ? 0.005 : 0.02
        let change = delta * multiplier
        let newVol = min(max(value + change, 0), 1)
        if abs(newVol - value) > 0.001 {
            value = newVol
            onValueChanged?(newVol)
        }
    }

    private func updateVolume(from event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let trackInset = Self.thumbRadius
        let trackWidth = bounds.width - (trackInset * 2)
        guard trackWidth > 0 else { return }
        let clampedX = min(max(point.x - trackInset, 0), trackWidth)
        let fraction = Float(clampedX / trackWidth)
        if abs(fraction - value) > 0.001 {
            value = fraction
            onValueChanged?(fraction)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let trackHeight = Self.trackHeight
        let thumbRadius = Self.thumbRadius
        let trackInset = thumbRadius
        let trackY = (bounds.height - trackHeight) / 2
        let trackWidth = bounds.width - (trackInset * 2)
        guard trackWidth > 0 else { return }

        let currentProgress = CGFloat(min(max(currentDrawnValue, 0), 1))
        let thumbCenterX = trackInset + trackWidth * currentProgress
        let thumbCenterY = bounds.height / 2

        drawTrackSegments(
            trackInset: trackInset,
            trackY: trackY,
            trackHeight: trackHeight,
            thumbCenterX: thumbCenterX,
            thumbRadius: thumbRadius
        )
        drawThumbRing(thumbCenterX: thumbCenterX, thumbCenterY: thumbCenterY)
    }

    private var activeGrayColor: NSColor {
        if isHovered || isDragging {
            return NSColor.secondaryLabelColor.blended(withFraction: 0.25, of: .labelColor)
                ?? NSColor.secondaryLabelColor
        }
        return NSColor.secondaryLabelColor
    }

    private func drawTrackSegments(
        trackInset: CGFloat,
        trackY: CGFloat,
        trackHeight: CGFloat,
        thumbCenterX: CGFloat,
        thumbRadius: CGFloat
    ) {
        let filledEnd = max(trackInset, thumbCenterX - thumbRadius)
        if filledEnd > trackInset {
            let filledRect = NSRect(x: trackInset, y: trackY, width: filledEnd - trackInset, height: trackHeight)
            let filledPath = NSBezierPath(roundedRect: filledRect, xRadius: trackHeight / 2, yRadius: trackHeight / 2)
            activeGrayColor.setFill()
            filledPath.fill()
        }

        let unfilledStart = min(bounds.width - trackInset, thumbCenterX + thumbRadius)
        let unfilledEnd = bounds.width - trackInset
        if unfilledEnd > unfilledStart {
            let rect = NSRect(x: unfilledStart, y: trackY, width: unfilledEnd - unfilledStart, height: trackHeight)
            let path = NSBezierPath(roundedRect: rect, xRadius: trackHeight / 2, yRadius: trackHeight / 2)
            let unfilledAlpha: CGFloat = (isHovered || isDragging) ? 0.18 : 0.12
            NSColor.labelColor.withAlphaComponent(unfilledAlpha).setFill()
            path.fill()
        }
    }

    private func drawThumbRing(thumbCenterX: CGFloat, thumbCenterY: CGFloat) {
        let radius = Self.thumbRadius
        let stroke = Self.ringStrokeWidth
        let ringRect = NSRect(
            x: thumbCenterX - radius + (stroke / 2),
            y: thumbCenterY - radius + (stroke / 2),
            width: Self.thumbDiameter - stroke,
            height: Self.thumbDiameter - stroke
        )

        let ringPath = NSBezierPath(ovalIn: ringRect)
        ringPath.lineWidth = stroke
        activeGrayColor.setStroke()
        ringPath.stroke()
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .slider }
    override func accessibilityLabel() -> String? { "Громкость" }
    override func accessibilityValue() -> Any? { "\(Int(value * 100))%" }
    override func accessibilityPerformIncrement() -> Bool {
        let newVol = min(value + 0.05, 1)
        value = newVol
        onValueChanged?(newVol)
        return true
    }
    override func accessibilityPerformDecrement() -> Bool {
        let newVol = max(value - 0.05, 0)
        value = newVol
        onValueChanged?(newVol)
        return true
    }
}
