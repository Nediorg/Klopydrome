import AppKit
import ObjectiveC
import SwiftUI

/// A transparent AppKit overlay that provides direct mouse interaction for sliders
/// and scrubbers in unified-toolbar titlebar regions.
///
/// In unified titlebar windows (`.windowToolbarStyle(.unified)`), pure SwiftUI views
/// cannot reliably intercept single-click drag gestures because AppKit hit-testing
/// returns `NSHostingView`, which defaults to `mouseDownCanMoveWindow = true` and
/// triggers `performWindowDragWithEvent:` on single-click mouse movements.
///
/// `InteractiveSliderTrack` solves this by placing a native `NSView` overlay on top of
/// the SwiftUI visuals:
/// 1. Overrides `mouseDownCanMoveWindow { false }` so AppKit never initiates window drag.
/// 2. Overrides `acceptsFirstMouse { true }` for immediate response on click.
/// 3. In `viewDidMoveToSuperview()`, enables hit-testing on its enclosing
///    `AppKitPlatformViewHost` so AppKit routes clicks directly to this view.
/// 4. In `mouseDown(with:)`, executes a modal tracking loop via `window.nextEvent`
///    for smooth single-click jumping and real-time dragging.
struct InteractiveSliderTrack: NSViewRepresentable {
    var onDragStarted: (() -> Void)?
    var onDragChanged: ((CGFloat) -> Void)?
    var onDragEnded: ((CGFloat) -> Void)?
    var onHoverChanged: ((Bool) -> Void)?
    var onScrollWheel: ((Float) -> Void)?
    var calculateProgress: ((CGPoint, CGSize) -> CGFloat)?

    func makeNSView(context: Context) -> InteractiveSliderTrackView {
        let view = InteractiveSliderTrackView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ nsView: InteractiveSliderTrackView, context: Context) {
        nsView.onDragStarted = onDragStarted
        nsView.onDragChanged = onDragChanged
        nsView.onDragEnded = onDragEnded
        nsView.onHoverChanged = onHoverChanged
        nsView.onScrollWheel = onScrollWheel
        nsView.calculateProgress = calculateProgress
    }
}

// MARK: - AppKit View Implementation

final class InteractiveSliderTrackView: NSView {
    private static var swizzledHostClasses = Set<ObjectIdentifier>()

    var onDragStarted: (() -> Void)?
    var onDragChanged: ((CGFloat) -> Void)?
    var onDragEnded: ((CGFloat) -> Void)?
    var onHoverChanged: ((Bool) -> Void)?
    var onScrollWheel: ((Float) -> Void)?
    var calculateProgress: ((CGPoint, CGSize) -> CGFloat)?

    private(set) var lastReportedProgress: CGFloat = 0
    private var trackingArea: NSTrackingArea?

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        guard let host = self.superview else { return }
        Self.ensureHostHitTestEnabled(on: type(of: host))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        self.trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }

    override func scrollWheel(with event: NSEvent) {
        if let onScrollWheel {
            let delta = Float(event.scrollingDeltaY + event.scrollingDeltaX * 0.5)
            let multiplier: Float = event.hasPreciseScrollingDeltas ? 0.005 : 0.02
            onScrollWheel(delta * multiplier)
        } else {
            super.scrollWheel(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        onDragStarted?()
        handleProgress(from: event)

        guard let window else {
            onDragEnded?(lastReportedProgress)
            return
        }

        var keepTracking = true
        while keepTracking {
            guard let nextEvent = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else {
                break
            }
            switch nextEvent.type {
            case .leftMouseDragged:
                handleProgress(from: nextEvent)
            case .leftMouseUp:
                handleProgress(from: nextEvent)
                onDragEnded?(lastReportedProgress)
                keepTracking = false
            default:
                break
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        handleProgress(from: event)
    }

    override func mouseUp(with event: NSEvent) {
        handleProgress(from: event)
        onDragEnded?(lastReportedProgress)
    }

    private func handleProgress(from event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        let progress = computeProgress(at: localPoint, size: bounds.size)
        lastReportedProgress = progress
        onDragChanged?(progress)
    }

    private func computeProgress(at point: CGPoint, size: CGSize) -> CGFloat {
        if let custom = calculateProgress {
            return custom(point, size)
        }
        guard size.width > 0 else { return 0 }
        return min(max(point.x / size.width, 0), 1)
    }

    // MARK: - Platform View Host Swizzling

    static func ensureHostHitTestEnabled(on hostClass: AnyClass) {
        let id = ObjectIdentifier(hostClass)
        guard !swizzledHostClasses.contains(id) else { return }
        swizzledHostClasses.insert(id)

        let selector = #selector(NSView.hitTest(_:))
        guard let originalMethod = class_getInstanceMethod(hostClass, selector) else { return }
        let originalIMP = method_getImplementation(originalMethod)

        typealias HitTestIMP = @convention(c) (AnyObject, Selector, NSPoint) -> NSView?
        let oldHitTest = unsafeBitCast(originalIMP, to: HitTestIMP.self)

        guard let superHitTestIMP = class_getMethodImplementation(NSView.self, selector) else { return }
        let superHitTest = unsafeBitCast(superHitTestIMP, to: HitTestIMP.self)

        let newHitTest: @convention(block) (AnyObject, NSPoint) -> NSView? = { (selfObj, point) in
            if let hit = superHitTest(selfObj, selector, point),
               hit is InteractiveSliderTrackView {
                return hit
            }
            return oldHitTest(selfObj, selector, point)
        }

        let newIMP = imp_implementationWithBlock(newHitTest)
        method_setImplementation(originalMethod, newIMP)
    }
}
