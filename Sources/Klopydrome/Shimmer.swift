import SwiftUI

/// A soft diagonal light band that travels across the view, used as a loading
/// skeleton. The band is wider than the view and its leading/trailing edges
/// are blurred out, so no hard sweep boundary ever appears inside the tile.
/// Honors Reduce Motion: with it on, a static gradient is shown instead of an
/// infinitely panning highlight.
struct Shimmer: ViewModifier {
    let enabled: Bool
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                if enabled {
                    ShimmerBand(phase: phase)
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

/// The traveling light band. Its gradient spans the whole overlay and is moved
/// as a unit; the sweep itself is a soft diagonal highlight with enough
/// translation to traverse the tile edge-to-edge.
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
    }
}

extension View {
    /// Overlays a moving light sweep, typically over a placeholder. Pass
    /// `false` when the loading state can never resolve (no artwork to fetch)
    /// so the tile stays a static placeholder instead of shimmering forever.
    func shimmering(_ enabled: Bool = true) -> some View {
        modifier(Shimmer(enabled: enabled))
    }
}
