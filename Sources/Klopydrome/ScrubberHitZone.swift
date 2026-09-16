import AppKit
import SwiftUI

/// A transparent NSView that reports `mouseDownCanMoveWindow = false`,
/// used as an underlay to prevent window dragging on interactive bars and containers.
struct NonDraggableBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NonDraggableNSView {
        NonDraggableNSView()
    }

    func updateNSView(_ nsView: NonDraggableNSView, context: Context) {}
}

final class NonDraggableNSView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
