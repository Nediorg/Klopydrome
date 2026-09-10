import SwiftUI

struct CrossfadeStatusLabel: View {
    let text: String
    var font: Font = .caption

    var body: some View {
        Label(text, systemImage: "arrow.triangle.merge")
            .font(font.weight(.medium))
            .foregroundStyle(AMColor.accent)
            .lineLimit(1)
            .accessibilityLabel(L10n.format("format.crossfade.accessibility", text.lowercased()))
    }
}
