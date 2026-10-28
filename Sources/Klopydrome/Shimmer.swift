import SwiftUI

struct Shimmer: ViewModifier {
    let enabled: Bool
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                if enabled && Motion.enabled {
                    ShimmerBand(phase: phase)
                        .allowsHitTesting(false)
                }
            }
            .clipped()
            .onAppear {
                guard enabled, Motion.enabled else { return }
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

struct ShimmerBand: View {
    let phase: CGFloat
    var body: some View {
        GeometryReader { geo in
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(0), location: 0),
                    .init(color: .white.opacity(0.16), location: 0.35),
                    .init(color: .white.opacity(0.16), location: 0.65),
                    .init(color: .white.opacity(0), location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .rotationEffect(.degrees(18))
            .scaleEffect(x: 0.85, y: 1.6)
            .offset(x: phase * geo.size.width * 2.2)
        }
        .allowsHitTesting(false)
    }
}

extension View {
    func shimmering(_ enabled: Bool = true) -> some View {
        modifier(Shimmer(enabled: enabled))
    }
}
