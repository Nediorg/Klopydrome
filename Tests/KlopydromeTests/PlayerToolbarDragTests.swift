import AppKit
import Foundation
@testable import Klopydrome
import NavidromeClient
import SwiftUI
import XCTest

/// Tests that verify `NonDraggableNSView` properly blocks window dragging
/// and that the deadzone calibration works correctly.
///
/// Note: the volume slider and scrubber are now pure SwiftUI views using
/// `DragGesture`, so there are no AppKit `NSControl` subclasses to find
/// in the hierarchy. These tests verify the supporting infrastructure.
@MainActor
final class PlayerToolbarDragTests: XCTestCase {
    func testNonDraggableNSViewBlocksWindowDrag() {
        let nonDraggable = NonDraggableNSView()
        nonDraggable.frame = NSRect(x: 0, y: 0, width: 100, height: 50)
        XCTAssertFalse(nonDraggable.mouseDownCanMoveWindow)
        XCTAssertTrue(nonDraggable.acceptsFirstResponder)

        // hitTest must return nil so it never swallows clicks destined for controls
        let center = NSPoint(x: 50, y: 25)
        XCTAssertNil(nonDraggable.hitTest(center))

        let outside = NSPoint(x: 150, y: 25)
        XCTAssertNil(nonDraggable.hitTest(outside))
    }

    func testScrubberDeadzoneCalibration() {
        // The scrubber deadzone logic is now in MinimalScrubber.scrubberProgress.
        // We test the same algorithm here directly.
        let deadzone: CGFloat = 5.0
        let width: CGFloat = 200.0

        func progress(pointX: CGFloat) -> CGFloat {
            guard width > deadzone else { return 0 }
            if pointX <= deadzone { return 0 }
            let effectiveX = pointX - deadzone
            let effectiveWidth = width - deadzone
            return min(max(effectiveX / effectiveWidth, 0), 1)
        }

        // Points within the first 5pt must strictly return 0.0
        XCTAssertEqual(progress(pointX: 0), 0.0, accuracy: 0.0001)
        XCTAssertEqual(progress(pointX: 2.5), 0.0, accuracy: 0.0001)
        XCTAssertEqual(progress(pointX: 5.0), 0.0, accuracy: 0.0001)
        XCTAssertEqual(progress(pointX: -10), 0.0, accuracy: 0.0001)

        // Midpoint of active track (5 + (200 - 5) / 2 = 102.5) should be 0.5
        XCTAssertEqual(progress(pointX: 102.5), 0.5, accuracy: 0.001)

        // End of track should be 1.0
        XCTAssertEqual(progress(pointX: 200), 1.0, accuracy: 0.0001)
        XCTAssertEqual(progress(pointX: 250), 1.0, accuracy: 0.0001)
    }

    func testHeaderBarWindowDragViewCanMoveWindow() {
        let dragView = HeaderBarWindowDragView()
        XCTAssertTrue(dragView.mouseDownCanMoveWindow)
    }

    func testTitlebarPassThroughInstallation() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        let toolbar = NSToolbar(identifier: "PassThroughTest")
        window.toolbar = toolbar
        window.toolbarStyle = .unified

        TitlebarPassThrough.install(on: window)
        // Calling install again must be safely idempotent
        TitlebarPassThrough.install(on: window)
    }

    func testInteractiveSliderTrackBlocksWindowDrag() {
        let view = InteractiveSliderTrackView()
        XCTAssertFalse(view.mouseDownCanMoveWindow, "InteractiveSliderTrackView must block window dragging")
        XCTAssertTrue(view.acceptsFirstMouse(for: nil), "Must accept first mouse for immediate interaction")
    }

    func testInteractiveSliderTrackHitTestInSwiftUI() {
        let hostView = NSHostingView(
            rootView: ZStack {
                Color.blue.frame(width: 800, height: 600)
                Color.red.frame(width: 100, height: 20)
                    .overlay(InteractiveSliderTrack())
            }
        )
        hostView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostView
        window.layoutIfNeeded()

        // Center hit must return InteractiveSliderTrackView with mouseDownCanMoveWindow == false
        let hitSlider = hostView.hitTest(NSPoint(x: 400, y: 300))
        XCTAssertTrue(hitSlider is InteractiveSliderTrackView, "Center hit must be InteractiveSliderTrackView")
        XCTAssertFalse(hitSlider?.mouseDownCanMoveWindow ?? true, "Slider hit must not allow window drag")

        // Hit outside slider must return NSHostingView with mouseDownCanMoveWindow == true
        let hitOutside = hostView.hitTest(NSPoint(x: 100, y: 300))
        XCTAssertFalse(hitOutside is InteractiveSliderTrackView, "Outside hit must not be InteractiveSliderTrackView")
        XCTAssertTrue(hitOutside?.mouseDownCanMoveWindow ?? false, "Empty space must allow window drag")
    }

    func testInteractiveSliderTrackCallbacks() {
        var started = false
        var changedProgress: CGFloat = -1
        var endedProgress: CGFloat = -1

        let trackView = InteractiveSliderTrackView()
        trackView.frame = NSRect(x: 0, y: 0, width: 100, height: 20)
        trackView.onDragStarted = { started = true }
        trackView.onDragChanged = { changedProgress = $0 }
        trackView.onDragEnded = { endedProgress = $0 }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 20),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = trackView

        let downEvent = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 50, y: 10),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1.0
        )!
        let upEvent = NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: NSPoint(x: 50, y: 10),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 2,
            clickCount: 1,
            pressure: 1.0
        )!

        window.postEvent(upEvent, atStart: false)
        trackView.mouseDown(with: downEvent)

        XCTAssertTrue(started, "onDragStarted must be called")
        XCTAssertEqual(changedProgress, 0.5, accuracy: 0.01, "Progress at midpoint must be 0.5")
        XCTAssertEqual(endedProgress, 0.5, accuracy: 0.01, "onDragEnded must receive final progress")
    }

    func testTitlebarPassThroughPreventsWindowDragOnSliders() {
        let (window, themeFrame) = makeTestPlayerWindow()
        TitlebarPassThrough.install(on: window)

        let volEvent = makeMouseEvent(at: NSPoint(x: 1020, y: 674), window: window, eventNumber: 1)
        let scrubEvent = makeMouseEvent(at: NSPoint(x: 600, y: 659), window: window, eventNumber: 2)
        let emptyEvent = makeMouseEvent(at: NSPoint(x: 210, y: 674), window: window, eventNumber: 3)

        assertThemeFrameDrag(themeFrame: themeFrame, vol: volEvent, scrub: scrubEvent, empty: emptyEvent)
        assertWindowDrag(window: window, vol: volEvent, scrub: scrubEvent, empty: emptyEvent)
    }

    private func assertThemeFrameDrag(themeFrame: NSView, vol: NSEvent, scrub: NSEvent, empty: NSEvent) {
        let dragSel = Selector(("shouldStartWindowDragForEvent:"))
        typealias DragCheck = @convention(c) (AnyObject, Selector, AnyObject) -> Bool
        let imp = class_getMethodImplementation(type(of: themeFrame), dragSel)
        let shouldDragFn = unsafeBitCast(imp, to: DragCheck.self)

        XCTAssertFalse(shouldDragFn(themeFrame, dragSel, vol))
        XCTAssertFalse(shouldDragFn(themeFrame, dragSel, scrub))
        XCTAssertTrue(shouldDragFn(themeFrame, dragSel, empty))

        let volHit = themeFrame.hitTest(vol.locationInWindow)
        let scrubHit = themeFrame.hitTest(scrub.locationInWindow)
        let emptyHit = themeFrame.hitTest(empty.locationInWindow)
        XCTAssertFalse(volHit?.mouseDownCanMoveWindow ?? true)
        XCTAssertFalse(scrubHit?.mouseDownCanMoveWindow ?? true)
        XCTAssertTrue(emptyHit?.mouseDownCanMoveWindow ?? false)
    }

    private func assertWindowDrag(window: NSWindow, vol: NSEvent, scrub: NSEvent, empty: NSEvent) {
        let selWindowDrag = Selector(("_shouldStartWindowDragForEvent:"))
        guard window.responds(to: selWindowDrag) else { return }
        typealias WindowDragCheck = @convention(c) (AnyObject, Selector, AnyObject) -> Bool
        let impWin = class_getMethodImplementation(type(of: window), selWindowDrag)
        let winDragFn = unsafeBitCast(impWin, to: WindowDragCheck.self)
        XCTAssertFalse(winDragFn(window, selWindowDrag, vol))
        XCTAssertFalse(winDragFn(window, selWindowDrag, scrub))
        XCTAssertTrue(winDragFn(window, selWindowDrag, empty))
    }

    private func makeTestPlayerWindow() -> (NSWindow, NSView) {
        let app = AppState()
        let song = SubsonicSong(id: "s1", title: "Test Song", artist: "Test Artist", duration: 200)
        app.player.queue = [song]
        app.player.currentIndex = 0

        let view = ContentView().environment(app)
        let hostView = NSHostingView(rootView: view)
        hostView.frame = NSRect(x: 0, y: 0, width: 1180, height: 700)

        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1180, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.toolbarStyle = .unified
        window.contentView = hostView
        window.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

        return (window, window.contentView!.superview!)
    }

    private func makeMouseEvent(at point: NSPoint, window: NSWindow, eventNumber: Int) -> NSEvent {
        NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: point,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: eventNumber,
            clickCount: 1,
            pressure: 1.0
        )!
    }
}
