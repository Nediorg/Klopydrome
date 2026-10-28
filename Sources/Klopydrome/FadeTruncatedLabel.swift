import SwiftUI

struct FadeTruncatedLabel: View {
    let text: String
    var font: Font = .system(size: 12)
    var color: Color = .primary

    var minLeading: CGFloat = 8
    var minTrailing: CGFloat = 24

    @State private var idealWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var marqueeOffset: CGFloat = 0

    private var availableWidth: CGFloat {
        max(0, containerWidth - minLeading - minTrailing)
    }

    private var isOverflowing: Bool {
        containerWidth > 0 && availableWidth > 0 && idealWidth > availableWidth + 1
    }

    private var marqueeDistance: CGFloat {
        max(0, idealWidth - availableWidth)
    }

    private var marqueeDuration: TimeInterval {
        max(4, TimeInterval(marqueeDistance / 24))
    }

    private var leadingSpace: CGFloat {
        guard containerWidth > 0, idealWidth > 0 else { return minLeading }
        if isOverflowing {
            return minLeading
        }
        let centered = (containerWidth - idealWidth) / 2
        let clampedLeading = max(minLeading, centered)
        if clampedLeading + idealWidth > containerWidth - minTrailing {
            return max(minLeading, containerWidth - minTrailing - idealWidth)
        }
        return clampedLeading
    }

    var body: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: leadingSpace, height: 1)

            ZStack(alignment: .leading) {
                if isOverflowing && marqueeOffset > 0 {
                    Text(text)
                        .font(font)
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .offset(x: -marqueeOffset)
                        .transition(.identity)
                } else {
                    Text(text)
                        .font(font)
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .transition(.identity)
                }
            }
            .frame(maxWidth: isOverflowing ? availableWidth : nil, alignment: .leading)
            .clipped()

            Spacer(minLength: minTrailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            Text(text)
                .font(font)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
                    idealWidth = $0
                }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
            containerWidth = $0
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
