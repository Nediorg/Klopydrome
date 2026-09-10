import SwiftUI

/// Corner overlay button for the lyrics panel (resume-follow, sync adjuster).
/// Hit box (28) is larger than the visible tile (26); label doubles as the
/// tooltip and VoiceOver name.
struct LyricsCornerControlButton: View {
    private static let visibleSize: CGFloat = 26
    private static let hitSize: CGFloat = 28
    private static let cornerRadius: CGFloat = 7

    let systemName: String
    let fill: Color
    var icon: Color = .white
    let showsBorder: Bool
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(icon)
                .frame(width: Self.visibleSize, height: Self.visibleSize)
                .background(fill, in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                        .strokeBorder(showsBorder ? AMColor.divider : .clear, lineWidth: 1)
                }
                .frame(width: Self.hitSize, height: Self.hitSize)
                .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(accessibilityLabel)
        .accessibilityLabel(accessibilityLabel)
    }
}
