import SwiftUI

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
