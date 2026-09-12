import SwiftUI

/// Single-line centered text that dissolves its trailing edge with a gradient
/// fade instead of a hard ellipsis when it overflows the available width.
///
/// Text remains centered and fully visible when it fits. When overflowing,
/// it aligns to the leading edge with a subtle gradient fade at the trailing edge,
/// and after a 3-second reading pause it smoothly scrolls across the available width.
struct FadeTruncatedLabel: View {
    let text: String
    var font: Font = .system(size: 12)
    var color: Color = .primary
    var leadingInset: CGFloat = 0
    var trailingInset: CGFloat = 0

    @State private var idealWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var marqueeOffset: CGFloat = 0

    private var availableWidth: CGFloat {
        max(0, containerWidth - leadingInset - trailingInset)
    }

    private var isOverflowing: Bool {
        availableWidth > 20 && idealWidth > availableWidth + 1
    }

    private var marqueeDistance: CGFloat {
        max(0, idealWidth - availableWidth)
    }

    private var marqueeDuration: TimeInterval {
        max(4, TimeInterval(marqueeDistance / 24))
    }

    var body: some View {
        ZStack(alignment: isOverflowing ? .leading : .center) {
            Text(text)
                .font(font)
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .offset(x: isOverflowing ? -marqueeOffset : 0)
                .background {
                    Text(text)
                        .font(font)
                        .fixedSize(horizontal: true, vertical: false)
                        .hidden()
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
                            idealWidth = $0
                        }
                }
        }
        .frame(maxWidth: .infinity, alignment: isOverflowing ? .leading : .center)
        .padding(.leading, leadingInset)
        .padding(.trailing, trailingInset)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
            containerWidth = $0
        }
        .mask {
            if isOverflowing {
                HStack(spacing: 0) {
                    if marqueeOffset > 4 {
                        LinearGradient(
                            colors: [.clear, .black],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 12)
                    }
                    Color.black
                    LinearGradient(
                        colors: [.black, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 12)
                }
                .padding(.leading, leadingInset)
                .padding(.trailing, trailingInset)
            } else {
                Color.black
            }
        }
        .task(id: MarqueeKey(text: text, idealWidth: idealWidth, availableWidth: availableWidth)) {
            await runMarquee()
        }
    }

    @MainActor
    private func runMarquee() async {
        guard isOverflowing, marqueeDistance > 2, Motion.enabled else {
            marqueeOffset = 0
            return
        }

        while !Task.isCancelled {
            marqueeOffset = 0
            guard await pause(for: 3.0) else { return }

            withAnimation(.linear(duration: marqueeDuration)) {
                marqueeOffset = marqueeDistance
            }
            guard await pause(for: marqueeDuration + 2.0) else { return }
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
        let availableWidth: CGFloat
    }
}
