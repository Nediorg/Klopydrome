import NavidromeClient
import SwiftUI

struct FadeTruncatedLabel: View {
    let text: String
    var font: Font = .system(size: 12)
    var color: Color = .primary
    var isHovered: Bool = false
    var lane: PlayerLCDMetrics.HorizontalLane = .init(minLeading: 8, minTrailing: 24)

    @State private var idealWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var marqueeStartDate: Date?

    private var placement: PlayerLCDMetrics.TextPlacement {
        PlayerLCDMetrics.placement(lcdWidth: containerWidth, textWidth: idealWidth, lane: lane)
    }

    private var scrollDistance: CGFloat {
        PlayerLCDMetrics.marqueeDistance(textWidth: idealWidth, availableWidth: placement.availableWidth)
    }

    private var shouldRunMarquee: Bool {
        isHovered && placement.isOverflowing && scrollDistance > 0 && Motion.enabled
    }

    var body: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: placement.leadingOffset, height: 1)

            labelViewport

            Spacer(minLength: lane.minTrailing)
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
        .task(id: MarqueeKey(
            text: text,
            idealWidth: Int(idealWidth.rounded()),
            availableWidth: Int(placement.availableWidth.rounded()),
            isHovered: isHovered
        )) {
            await armMarquee()
        }
    }

    @ViewBuilder
    private var labelViewport: some View {
        if let startDate = marqueeStartDate, shouldRunMarquee {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
                let elapsed = max(0, context.date.timeIntervalSince(startDate))
                let offset = PlayerLCDMetrics.marqueeOffset(elapsed: elapsed, distance: scrollDistance)

                Text(text)
                    .font(font)
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .offset(x: -offset)
                    .frame(width: placement.availableWidth, alignment: .leading)
                    .clipped()
                    .mask(edgeFadeMask(
                        width: placement.availableWidth,
                        showLeadingFade: offset > 0.5,
                        showTrailingFade: (scrollDistance - offset) > 0.5
                    ))
            }
        } else {
            Text(text)
                .font(font)
                .foregroundStyle(color)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: placement.isOverflowing ? placement.availableWidth : nil, alignment: .leading)
        }
    }

    private func edgeFadeMask(
        width: CGFloat,
        showLeadingFade: Bool,
        showTrailingFade: Bool
    ) -> some View {
        let fadeFraction = width > 0 ? min(0.18, PlayerLCDMetrics.marqueeEdgeFadeWidth / width) : 0
        return LinearGradient(
            stops: [
                .init(color: showLeadingFade ? .clear : .black, location: 0),
                .init(color: .black, location: showLeadingFade ? fadeFraction : 0),
                .init(color: .black, location: showTrailingFade ? max(0, 1 - fadeFraction) : 1),
                .init(color: showTrailingFade ? .clear : .black, location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    @MainActor
    private func armMarquee() async {
        marqueeStartDate = nil
        guard shouldRunMarquee else { return }
        do {
            try await Task.sleep(for: .seconds(PlayerLCDMetrics.marqueeStartDelay))
        } catch {
            return
        }
        guard !Task.isCancelled, shouldRunMarquee else { return }
        marqueeStartDate = Date()
    }

    private struct MarqueeKey: Hashable {
        let text: String
        let idealWidth: Int
        let availableWidth: Int
        let isHovered: Bool
    }
}
