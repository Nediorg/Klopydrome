import SwiftUI

/// Compact volume control styled as a matte progress track. Unlike the native
/// slider, its visual track and interactive bounds are identical.
struct MatteVolumeSlider: View {
    @Binding var value: Float

    private let trackHeight: CGFloat = 6
    private let thumbDiameter: CGFloat = 18

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let progress = CGFloat(min(max(value, 0), 1))
            let thumbCenter = min(
                max(width * progress, thumbDiameter / 2),
                max(thumbDiameter / 2, width - thumbDiameter / 2)
            )

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.black.opacity(0.34))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(.white.opacity(0.58))
                    .frame(width: width * progress, height: trackHeight)

                Circle()
                    .fill(.white.opacity(0.78))
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .shadow(color: .black.opacity(0.24), radius: 2, y: 1)
                    .offset(x: thumbCenter - thumbDiameter / 2)
            }
            .frame(width: width, height: thumbDiameter)
            .contentShape(Rectangle())
            .gesture(volumeGesture(width: width))
        }
        .frame(height: thumbDiameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Громкость")
        .accessibilityValue("\(Int((value * 100).rounded()))%")
        .accessibilityAdjustableAction { direction in
            let delta: Float = direction == .increment ? 0.05 : -0.05
            value = min(max(value + delta, 0), 1)
        }
    }

    private func volumeGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                guard width > 0 else { return }
                value = Float(min(max(gesture.location.x / width, 0), 1))
            }
    }
}
