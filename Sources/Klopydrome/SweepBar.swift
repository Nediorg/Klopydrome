import SwiftUI

struct SweepBar: View {
    let width: CGFloat
    let trackHeight: CGFloat

    private let cycleSeconds: Double = 1.3

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !Motion.enabled)) { context in
            let offsetFraction: CGFloat = {
                guard Motion.enabled else { return 0.25 }
                let t = context.date.timeIntervalSinceReferenceDate
                let phase = t.truncatingRemainder(dividingBy: cycleSeconds) / cycleSeconds
                return -0.5 + CGFloat(phase) * 1.65
            }()

            Rectangle()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: AMColor.accent.opacity(0), location: 0),
                            .init(color: AMColor.accent.opacity(0.9), location: 0.5),
                            .init(color: AMColor.accent.opacity(0), location: 1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: max(16, width * 0.45), height: trackHeight)
                .offset(x: offsetFraction * width)
        }
    }
}
