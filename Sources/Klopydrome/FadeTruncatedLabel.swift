import SwiftUI

/// Single-line centered text that dissolves its trailing edge with a gradient
/// fade instead of a hard ellipsis when it overflows the available width.
///
/// The mask is applied only when the text actually truncates: a hidden
/// `.fixedSize()` copy reports the text's ideal (untruncated) width and the
/// visible line (`.frame(maxWidth: .infinity)`) reports the container width.
/// Leading and trailing insets reserve space for hover markers and actions.
/// Text remains centered when it fits. An overflowing line begins at the
/// leading edge of its safe area and repeatedly traverses the available width.
/// Both widths are measured with `onGeometryChange` (no greedy `GeometryReader`,
/// which the `.principal` toolbar placement must not contain).
struct FadeTruncatedLabel: View {
    let text: String
    var font: Font = .system(size: 12)
    var color: Color = .primary
    var leadingInset: CGFloat = 0
    var trailingInset: CGFloat = 0

    @State private var idealWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var marqueeOffset: CGFloat = 0

    private var visibleWidth: CGFloat {
        max(0, containerWidth - leadingInset - trailingInset)
    }

    private var isOverflowing: Bool {
        idealWidth > visibleWidth
    }

    /// Moves the centered safe rectangle onto the globally centered canvas.
    private var safeAreaOffset: CGFloat {
        (leadingInset - trailingInset) / 2
    }

    /// Distance required to reveal the end of an overflowing line at the
    /// trailing edge of the available text region.
    private var marqueeDistance: CGFloat {
        max(0, idealWidth - visibleWidth)
    }

    private var marqueeDuration: TimeInterval {
        max(4, TimeInterval(marqueeDistance / 24))
    }

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize(horizontal: isOverflowing, vertical: false)
            .frame(width: isOverflowing ? visibleWidth : nil, alignment: .leading)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .center)
            .offset(x: isOverflowing ? safeAreaOffset - marqueeOffset : 0)
            .background {
                Text(text)
                    .font(font)
                    .fixedSize(horizontal: true, vertical: false)
                    .hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
                        idealWidth = $0
                    }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
                containerWidth = $0
            }
            .mask {
                HStack(spacing: 0) {
                    Color.clear.frame(width: leadingInset)
                    Color.black
                    Color.clear.frame(width: trailingInset)
                }
                .frame(maxWidth: .infinity)
            }
            .task(id: MarqueeKey(text: text, idealWidth: idealWidth, visibleWidth: visibleWidth)) {
                await runMarquee()
            }
    }

    @MainActor
    private func runMarquee() async {
        guard isOverflowing, marqueeDistance > 0, Motion.enabled else {
            marqueeOffset = 0
            return
        }

        while !Task.isCancelled {
            marqueeOffset = 0
            guard await pause(for: 1) else { return }

            withAnimation(.linear(duration: marqueeDuration)) {
                marqueeOffset = marqueeDistance
            }
            guard await pause(for: marqueeDuration + 1) else { return }
        }
    }

    private func pause(for duration: TimeInterval) async -> Bool {
        do {
            try await Task.sleep(for: .seconds(duration))
            return !Task.isCancelled
        } catch {
            return false
        }
    }

    private struct MarqueeKey: Hashable {
        let text: String
        let idealWidth: CGFloat
        let visibleWidth: CGFloat
    }
}
