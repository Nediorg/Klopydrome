import SwiftUI

/// Indeterminate loading sweep shown in the mini-player scrubber while the
/// track buffers. The animation is owned by this subview and therefore exists
/// only for its lifetime: it starts on appear and is torn down automatically
/// when the parent stops showing it (i.e. when loading ends). This avoids the
/// previous bug where a `repeatForever` launched from the parent kept mutating
/// a `@State` on the scrubber forever, re-laying-out the toolbar ~60 fps and
/// saturating the main thread.
struct SweepBar: View {
    let width: CGFloat
    let trackHeight: CGFloat

    @State private var offset: CGFloat = -0.5

    var body: some View {
        Capsule()
            .fill(LinearGradient(
                stops: [
                    .init(color: .white.opacity(0), location: 0),
                    .init(color: .white.opacity(1), location: 0.5),
                    .init(color: .white.opacity(0), location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing))
            .frame(width: width * 0.5, height: trackHeight)
            .offset(x: offset * width)
            .task {
                offset = -0.5
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                    offset = 1.2
                }
            }
    }
}
