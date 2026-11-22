import SwiftUI

struct SweepBar: View {
    let width: CGFloat
    let trackHeight: CGFloat

    @State private var offset: CGFloat = -0.5

    var body: some View {
        Capsule()
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: AMColor.accent.opacity(0), location: 0),
                        .init(color: AMColor.accent.opacity(0.85), location: 0.5),
                        .init(color: AMColor.accent.opacity(0), location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: max(16, width * 0.45), height: trackHeight)
            .offset(x: offset * width)
            .onAppear {
                guard Motion.enabled, !ProcessInfo.processInfo.isLowPowerModeEnabled else {
                    offset = 0.25
                    return
                }
                offset = -0.5
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                    offset = 1.2
                }
            }
    }
}
