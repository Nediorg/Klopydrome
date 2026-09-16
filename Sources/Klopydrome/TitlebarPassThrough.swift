import AppKit
import ObjectiveC
import SwiftUI

/// Resolves titlebar event occlusion in unified-toolbar windows.
///
/// Under `.windowToolbarStyle(.unified)` + `.fullSizeContentView`, AppKit's
/// `NSThemeFrame` places `NSTitlebarContainerView` (height 52 pt) *above*
/// `contentView` in the z-order. Because Klopydrome renders `PlayerHeaderBar`
/// in `contentView` rather than inside `NSToolbarItem`s, `NSToolbarView` treats
/// the entire header region as empty toolbar background and intercepts single-click
/// `mouseDown` events to move the window.
///
/// This helper swizzles `hitTest(_:)` on `NSTitlebarContainerView` so that any hit
/// on empty titlebar/toolbar background outside the traffic lights (window x > 80 pt)
/// returns `nil`. This lets `NSThemeFrame` fall through to `contentView`, giving
/// controls in `PlayerHeaderBar` (volume slider, scrubber, transport buttons)
/// direct single-click and drag events without interference.
enum TitlebarPassThrough {
    private static var isInstalled = false

    @MainActor
    static func installGlobal() {
        guard !isInstalled else { return }
        isInstalled = true

        if let themeFrameClass = NSClassFromString("NSThemeFrame") {
            swizzleThemeFrameDrag(on: themeFrameClass)
        }

        swizzleWindowDrag(on: NSWindow.self)

        if let titlebarClass = NSClassFromString("NSTitlebarContainerView") {
            swizzleHitTest(on: titlebarClass)
        }
    }

    @MainActor
    static func install(on window: NSWindow? = nil) {
        installGlobal()
    }

    private static func swizzleThemeFrameDrag(on themeFrameClass: AnyClass) {
        let dragSel = Selector(("shouldStartWindowDragForEvent:"))
        guard let originalMethod = class_getInstanceMethod(themeFrameClass, dragSel) else { return }

        typealias DragIMP = @convention(c) (AnyObject, Selector, AnyObject) -> Bool
        let originalIMP = method_getImplementation(originalMethod)
        let oldDragFn = unsafeBitCast(originalIMP, to: DragIMP.self)

        let swizzledBlock: @convention(block) (AnyObject, AnyObject) -> Bool = { (selfObj, eventObj) in
            guard let event = eventObj as? NSEvent, let frameView = selfObj as? NSView else {
                return oldDragFn(selfObj, dragSel, eventObj)
            }
            // If the view directly under the cursor explicitly disallows window moving
            // (e.g. volume sliders, scrubbers, interactive controls), do NOT initiate a window drag.
            if let hit = frameView.hitTest(event.locationInWindow), !hit.mouseDownCanMoveWindow {
                return false
            }
            return oldDragFn(selfObj, dragSel, eventObj)
        }

        let newIMP = imp_implementationWithBlock(swizzledBlock)
        method_setImplementation(originalMethod, newIMP)
    }

    private static func swizzleWindowDrag(on windowClass: AnyClass) {
        let dragSel = Selector(("_shouldStartWindowDragForEvent:"))
        guard let originalMethod = class_getInstanceMethod(windowClass, dragSel) else { return }

        typealias DragIMP = @convention(c) (AnyObject, Selector, AnyObject) -> Bool
        let originalIMP = method_getImplementation(originalMethod)
        let oldDragFn = unsafeBitCast(originalIMP, to: DragIMP.self)

        let swizzledBlock: @convention(block) (AnyObject, AnyObject) -> Bool = { (selfObj, eventObj) in
            guard let event = eventObj as? NSEvent, let window = selfObj as? NSWindow else {
                return oldDragFn(selfObj, dragSel, eventObj)
            }
            if let root = window.contentView?.superview,
               let hit = root.hitTest(event.locationInWindow),
               !hit.mouseDownCanMoveWindow {
                return false
            }
            return oldDragFn(selfObj, dragSel, eventObj)
        }

        let newIMP = imp_implementationWithBlock(swizzledBlock)
        method_setImplementation(originalMethod, newIMP)
    }

    private static func swizzleHitTest(on targetClass: AnyClass) {
        let originalSelector = #selector(NSView.hitTest(_:))
        let swizzledSelector = #selector(NSView.klopydrome_titlebarHitTest(_:))

        guard let swizzledMethod = class_getInstanceMethod(NSView.self, swizzledSelector) else {
            return
        }

        if let originalMethod = class_getInstanceMethod(targetClass, originalSelector) {
            let didAddMethod = class_addMethod(
                targetClass,
                swizzledSelector,
                method_getImplementation(originalMethod),
                method_getTypeEncoding(originalMethod)
            )

            if didAddMethod {
                class_replaceMethod(
                    targetClass,
                    originalSelector,
                    method_getImplementation(swizzledMethod),
                    method_getTypeEncoding(swizzledMethod)
                )
            } else {
                method_exchangeImplementations(originalMethod, swizzledMethod)
            }
        }
    }
}

// MARK: - Swizzled hitTest on NSView

extension NSView {
    @objc func klopydrome_titlebarHitTest(_ point: NSPoint) -> NSView? {
        // Calls the original hitTest implementation (swizzled)
        guard let hit = self.klopydrome_titlebarHitTest(point) else {
            return nil
        }

        // Always keep actual interactive controls (close/minimize/zoom buttons, toolbar buttons)
        if hit is NSButton || hit is NSControl {
            return hit
        }

        let hitTypeName = String(describing: type(of: hit))
        if hitTypeName.contains("Button")
            || hitTypeName.contains("Control")
            || hitTypeName.contains("Widget")
            || hitTypeName.contains("ItemViewer") {
            return hit
        }

        // Traffic lights are on the leading edge (x < 80 pt in window space).
        // Clicks past traffic lights belong to PlayerHeaderBar in contentView.
        // Returning nil lets NSThemeFrame fall through to contentView.
        if point.x > 80 {
            return nil
        }

        return hit
    }
}

// MARK: - Header Bar Window Drag Region

/// A native hit-test region that allows dragging the window when clicking on
/// empty background space in PlayerHeaderBar, matching Apple Music behavior.
struct HeaderBarWindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> HeaderBarWindowDragView {
        HeaderBarWindowDragView()
    }

    func updateNSView(_ nsView: HeaderBarWindowDragView, context: Context) {}
}

final class HeaderBarWindowDragView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
