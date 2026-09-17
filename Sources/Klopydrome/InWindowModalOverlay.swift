import AppKit
import SwiftUI

/// Shared styling for centered elevated modal inspection cards.
struct InWindowModalCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AMColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 30, x: 0, y: 12)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .onTapGesture {
                // Absorb taps on background/padding of the card so backdrop doesn't receive them
            }
    }
}

extension View {
    func inWindowModalCardStyle() -> some View {
        modifier(InWindowModalCardModifier())
    }
}

/// A centered in-window modal card presentation with an interactive dimmed backdrop.
///
/// Backdrop strictly transitions with `.opacity` and never scales.
/// Card transitions with `.opacity.combined(with: .scale(scale: 0.96))`.
struct InWindowModalOverlay<Content: View>: View {
    @Binding var isPresented: Bool
    @ViewBuilder let content: () -> Content

    init(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._isPresented = isPresented
        self.content = content
    }

    var body: some View {
        ZStack {
            if isPresented {
                // 1. Semi-transparent backdrop with click-to-dismiss (STRICTLY opacity, NO scale)
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismiss()
                    }
                    .transition(.opacity)

                // 2. Centered elevated card (opacity + scale 0.96)
                content()
                    .inWindowModalCardStyle()
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.snappy(duration: 0.2), value: isPresented)
        .allowsHitTesting(isPresented)
        .onKeyPress(.escape) {
            guard isPresented else { return .ignored }
            dismiss()
            return .handled
        }
        .background {
            if isPresented {
                Button("") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .opacity(0)
                    .allowsHitTesting(false)
            }
        }
    }

    private func dismiss() {
        withAnimation(.snappy(duration: 0.2)) {
            isPresented = false
        }
    }
}

/// An item-based in-window modal card overlay with state retention during exit animation.
///
/// Keeps `retainedItem` populated while the 0.2s exit animation runs so that
/// the card content does not vanish or encounter `nil` state before it finishes fading and scaling down.
struct InWindowModalItemOverlay<Item: Identifiable, Content: View>: View {
    @Binding var item: Item?
    @ViewBuilder let content: (Item) -> Content

    @State private var retainedItem: Item?

    init(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> Content
    ) {
        self._item = item
        self.content = content
    }

    var body: some View {
        ZStack {
            if let displayItem = retainedItem {
                // 1. Semi-transparent backdrop with click-to-dismiss (STRICTLY opacity, NO scale)
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismiss()
                    }
                    .transition(.opacity)

                // 2. Centered elevated card (opacity + scale 0.96)
                content(displayItem)
                    .inWindowModalCardStyle()
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.snappy(duration: 0.2), value: retainedItem != nil)
        .allowsHitTesting(retainedItem != nil)
        .onKeyPress(.escape) {
            guard retainedItem != nil else { return .ignored }
            dismiss()
            return .handled
        }
        .background {
            if retainedItem != nil {
                Button("") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .opacity(0)
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            retainedItem = item
        }
        .onChange(of: item?.id) { _, _ in
            if let newItem = item {
                withAnimation(.snappy(duration: 0.2)) {
                    retainedItem = newItem
                }
            } else {
                withAnimation(.snappy(duration: 0.2)) {
                    retainedItem = nil
                }
            }
        }
    }

    private func dismiss() {
        withAnimation(.snappy(duration: 0.2)) {
            item = nil
            retainedItem = nil
        }
    }
}

// MARK: - View Extension API

extension View {
    /// Presents an in-window modal card overlay using a Boolean binding.
    func inWindowModal<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        overlay {
            InWindowModalOverlay(isPresented: isPresented, content: content)
        }
    }

    /// Presents an in-window modal card overlay using an optional Identifiable item binding,
    /// retaining the item during dismissal animations.
    func inWindowModal<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        overlay {
            InWindowModalItemOverlay(item: item, content: content)
        }
    }
}
