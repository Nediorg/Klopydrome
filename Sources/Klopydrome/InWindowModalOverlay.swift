import AppKit
import SwiftUI

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
            }
    }
}

extension View {
    func inWindowModalCardStyle() -> some View {
        modifier(InWindowModalCardModifier())
    }
}

struct InWindowModalAttemptDismissAction: Equatable {
    let id: String
    let action: () -> Void

    init(id: String = UUID().uuidString, action: @escaping () -> Void) {
        self.id = id
        self.action = action
    }

    static func == (lhs: InWindowModalAttemptDismissAction, rhs: InWindowModalAttemptDismissAction) -> Bool {
        lhs.id == rhs.id
    }
}

struct InWindowModalAttemptDismissKey: PreferenceKey {
    static var defaultValue: InWindowModalAttemptDismissAction?
    static func reduce(
        value: inout InWindowModalAttemptDismissAction?,
        nextValue: () -> InWindowModalAttemptDismissAction?
    ) {
        value = nextValue() ?? value
    }
}

struct InWindowModalOverlay<Content: View>: View {
    @Binding var isPresented: Bool
    var onAttemptDismiss: (() -> Void)?
    @ViewBuilder let content: () -> Content

    @State private var interceptDismiss: InWindowModalAttemptDismissAction?

    init(
        isPresented: Binding<Bool>,
        onAttemptDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._isPresented = isPresented
        self.onAttemptDismiss = onAttemptDismiss
        self.content = content
    }

    var body: some View {
        ZStack {
            if isPresented {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        attemptDismiss()
                    }
                    .transition(.opacity)

                content()
                    .inWindowModalCardStyle()
                    .onPreferenceChange(InWindowModalAttemptDismissKey.self) { action in
                        interceptDismiss = action
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.snappy(duration: 0.2), value: isPresented)
        .allowsHitTesting(isPresented)
        .onKeyPress(.escape) {
            guard isPresented else { return .ignored }
            attemptDismiss()
            return .handled
        }
        .background {
            if isPresented {
                Button("") { attemptDismiss() }
                    .keyboardShortcut(.cancelAction)
                    .opacity(0)
                    .allowsHitTesting(false)
            }
        }
    }

    private func attemptDismiss() {
        if let onAttemptDismiss {
            onAttemptDismiss()
        } else if let interceptDismiss {
            interceptDismiss.action()
        } else {
            dismiss()
        }
    }

    private func dismiss() {
        withAnimation(.snappy(duration: 0.2)) {
            isPresented = false
        }
    }
}

struct InWindowModalItemOverlay<Item: Identifiable, Content: View>: View {
    @Binding var item: Item?
    var onAttemptDismiss: (() -> Void)?
    @ViewBuilder let content: (Item) -> Content

    @State private var retainedItem: Item?
    @State private var interceptDismiss: InWindowModalAttemptDismissAction?

    init(
        item: Binding<Item?>,
        onAttemptDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) {
        self._item = item
        self.onAttemptDismiss = onAttemptDismiss
        self.content = content
    }

    var body: some View {
        ZStack {
            if let displayItem = retainedItem {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        attemptDismiss()
                    }
                    .transition(.opacity)

                content(displayItem)
                    .inWindowModalCardStyle()
                    .onPreferenceChange(InWindowModalAttemptDismissKey.self) { action in
                        interceptDismiss = action
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.snappy(duration: 0.2), value: retainedItem != nil)
        .allowsHitTesting(retainedItem != nil)
        .onKeyPress(.escape) {
            guard retainedItem != nil else { return .ignored }
            attemptDismiss()
            return .handled
        }
        .background {
            if retainedItem != nil {
                Button("") { attemptDismiss() }
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

    private func attemptDismiss() {
        if let onAttemptDismiss {
            onAttemptDismiss()
        } else if let interceptDismiss {
            interceptDismiss.action()
        } else {
            dismiss()
        }
    }

    private func dismiss() {
        withAnimation(.snappy(duration: 0.2)) {
            item = nil
            retainedItem = nil
        }
    }
}

extension View {
    func onInWindowModalAttemptDismiss(id: String = "default", _ action: @escaping () -> Void) -> some View {
        preference(
            key: InWindowModalAttemptDismissKey.self,
            value: InWindowModalAttemptDismissAction(id: id, action: action)
        )
    }

    func inWindowModal<Content: View>(
        isPresented: Binding<Bool>,
        onAttemptDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        overlay {
            InWindowModalOverlay(isPresented: isPresented, onAttemptDismiss: onAttemptDismiss, content: content)
        }
    }

    func inWindowModal<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        onAttemptDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        overlay {
            InWindowModalItemOverlay(item: item, onAttemptDismiss: onAttemptDismiss, content: content)
        }
    }
}
