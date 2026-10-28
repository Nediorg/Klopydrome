import SwiftUI

struct VolumeEdgeButton: View {
    private static let hitBoxSide: CGFloat = 28

    let systemImage: String
    let label: String
    var symbolOffset: CGFloat = 0
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11))
                .foregroundStyle(isHovering ? Color.primary.opacity(0.9) : Color.secondary)
                .offset(x: symbolOffset)
                .frame(width: Self.hitBoxSide, height: Self.hitBoxSide)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}
