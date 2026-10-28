import SwiftUI
import NavidromeClient

struct MediaCard<Artwork: View, TrailingBadge: View>: View {
    var width: CGFloat? = 165
    let title: String
    var subtitle: String?
    var line2: String?
    var reservesTitleLines: Bool = true
    @ViewBuilder let artwork: () -> Artwork
    @ViewBuilder var trailingBadge: () -> TrailingBadge

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 6) {
                artworkContainer
                textBlock
            }
            .frame(width: width, alignment: .leading)
            .foregroundStyle(.primary)

            trailingBadge()
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var artworkContainer: some View {
        if let width {
            artwork()
                .frame(width: width, height: width)
        } else {
            GeometryReader { geo in
                artwork()
                    .frame(width: geo.size.width, height: geo.size.width)
            }
            .aspectRatio(1, contentMode: .fit)
        }
    }

    @ViewBuilder
    private var textBlock: some View {
        if reservesTitleLines {
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Title\nLine2")
                        .font(AMFont.cardTitle)
                        .lineLimit(2)
                    if subtitle?.isEmpty == false {
                        Text("Subtitle").font(AMFont.cardSubtitle)
                    }
                    if line2?.isEmpty == false {
                        Text("0000").font(AMFont.cardSubtitle)
                    }
                }
                .hidden()
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    titleLines
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 1) {
                titleLines
            }
        }
    }

    @ViewBuilder
    private var titleLines: some View {
        Text(title)
            .font(AMFont.cardTitle)
            .lineLimit(reservesTitleLines ? 2 : 1)
        if let subtitle, !subtitle.isEmpty {
            Text(subtitle)
                .font(AMFont.cardSubtitle)
                .foregroundStyle(AMColor.secondaryText)
                .lineLimit(1)
        }
        if let line2, !line2.isEmpty {
            Text(line2)
                .font(AMFont.cardSubtitle)
                .foregroundStyle(AMColor.secondaryText)
                .lineLimit(1)
        }
    }
}

extension MediaCard where TrailingBadge == EmptyView {
    init(
        width: CGFloat? = 165,
        title: String,
        subtitle: String? = nil,
        line2: String? = nil,
        reservesTitleLines: Bool = true,
        @ViewBuilder artwork: @escaping () -> Artwork
    ) {
        self.width = width
        self.title = title
        self.subtitle = subtitle
        self.line2 = line2
        self.reservesTitleLines = reservesTitleLines
        self.artwork = artwork
        self.trailingBadge = { EmptyView() }
    }
}
