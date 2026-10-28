import SwiftUI

struct SkeletonSongRow: View {
    var showAlbum: Bool = true
    var showsArtist: Bool = true
    var forMask: Bool = false

    private var isNarrow: Bool { !showAlbum && !showsArtist }

    var body: some View {
        HStack(spacing: 6) {
            Color.clear
                .frame(width: 16, height: 16)

            HStack(spacing: 10) {
                HStack(spacing: showAlbum ? 8 : 10) {
                    if showAlbum {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(forMask ? Color.black : Color.primary.opacity(0.06))
                            .frame(width: 36, height: 36)
                    } else {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(forMask ? Color.black : Color.primary.opacity(0.05))
                            .frame(width: 14, height: 10)
                            .frame(width: 22, height: isNarrow ? 20 : nil, alignment: .trailing)
                    }

                    VStack(alignment: .leading, spacing: isNarrow ? 0 : 3) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(forMask ? Color.black : Color.primary.opacity(0.07))
                            .frame(width: 160, height: 12)

                        if showAlbum || showsArtist {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(forMask ? Color.black : Color.primary.opacity(0.05))
                                .frame(width: 110, height: 10)
                        }
                    }
                }

                Spacer(minLength: 8)

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(forMask ? Color.black : Color.primary.opacity(0.04))
                    .frame(width: 36, height: 10)
            }
            .padding(.leading, showAlbum ? 5 : 8)
            .padding(.trailing, 8)
            .padding(.vertical, isNarrow ? 2 : 5)
            .frame(height: isNarrow ? 26 : nil)
        }
        .frame(height: showAlbum ? 46 : (showsArtist ? 40 : 32))
    }
}

struct SkeletonSongList: View {
    var count: Int = 10
    var showAlbum: Bool = true
    var showsArtist: Bool = true

    var body: some View {
        rows(forMask: false)
            .shimmering()
            .mask {
                rows(forMask: true)
            }
    }

    private func rows(forMask: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { _ in
                SkeletonSongRow(showAlbum: showAlbum, showsArtist: showsArtist, forMask: forMask)
            }
        }
    }
}

struct SkeletonCard: View {
    var size: CGFloat = 150
    var isCircle: Bool = false
    var forMask: Bool = false

    var body: some View {
        VStack(alignment: isCircle ? .center : .leading, spacing: 6) {
            if isCircle {
                Circle()
                    .fill(forMask ? Color.black : Color.primary.opacity(0.08))
                    .frame(width: size, height: size)
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(forMask ? Color.black : Color.primary.opacity(0.08))
                    .frame(width: size, height: size)
            }

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(forMask ? Color.black : Color.primary.opacity(0.08))
                .frame(width: size * 0.7, height: 11)

            if !isCircle {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(forMask ? Color.black : Color.primary.opacity(0.05))
                    .frame(width: size * 0.45, height: 9)
            }
        }
    }
}

struct SkeletonCardShelf: View {
    var count: Int = 4
    var cardSize: CGFloat = 150
    var isCircle: Bool = false
    var spacing: CGFloat = 12

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            cards(forMask: false)
                .shimmering()
                .mask {
                    cards(forMask: true)
                }
        }
        .scrollClipDisabled()
        .fixedSize(horizontal: false, vertical: true)
    }

    private func cards(forMask: Bool) -> some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(0..<count, id: \.self) { _ in
                SkeletonCard(size: cardSize, isCircle: isCircle, forMask: forMask)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }
}

struct SkeletonCardGrid: View {
    var count: Int = 12
    var minCard: CGFloat = 160
    var gap: CGFloat = 16
    var isCircle: Bool = false
    var horizontalPadding: CGFloat = 24
    var verticalPadding: CGFloat = 20
    var accessibilityLabel: String?

    var body: some View {
        GeometryReader { geo in
            let available = max(0, geo.size.width - horizontalPadding * 2)
            let colCount = max(1, Int((available + gap) / (minCard + gap)))
            let rawWidth = (available - CGFloat(colCount - 1) * gap) / CGFloat(colCount)
            let cardWidth = floor(rawWidth)
            let cols = Array(repeating: GridItem(.fixed(cardWidth), spacing: gap), count: colCount)

            ScrollView {
                grid(cols: cols, cardWidth: cardWidth, forMask: false)
                    .shimmering()
                    .mask {
                        grid(cols: cols, cardWidth: cardWidth, forMask: true)
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, verticalPadding)
            }
            .scrollClipDisabled()
        }
        .accessibilityLabel(accessibilityLabel ?? "Loading".localized)
    }

    private func grid(cols: [GridItem], cardWidth: CGFloat, forMask: Bool) -> some View {
        LazyVGrid(columns: cols, spacing: gap) {
            ForEach(0..<count, id: \.self) { _ in
                SkeletonCard(size: cardWidth, isCircle: isCircle, forMask: forMask)
            }
        }
    }
}

struct SkeletonCompactSongColumn: View {
    var count: Int = 3
    var width: CGFloat = 280

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { index in
                    Color.clear.frame(height: 48)
                    if index < count - 1 {
                        Divider()
                            .padding(.leading, 50)
                            .padding(.trailing, 6)
                            .opacity(0.4)
                    }
                }
            }

            rows(forMask: false)
                .shimmering()
                .mask {
                    rows(forMask: true)
                }
        }
        .frame(width: width)
    }

    private func rows(forMask: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(forMask ? Color.black : Color.primary.opacity(0.08))
                        .frame(width: 36, height: 36)

                    VStack(alignment: .leading, spacing: 3) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(forMask ? Color.black : Color.primary.opacity(0.10))
                            .frame(width: 130, height: 12)

                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .fill(forMask ? Color.black : Color.primary.opacity(0.06))
                            .frame(width: 80, height: 9)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)

                if index < count - 1 {
                    Color.clear.frame(height: 1)
                }
            }
        }
        .frame(width: width)
    }
}

struct SkeletonPillCard: View {
    var forMask: Bool = false

    var body: some View {
        if forMask {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
        } else {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 90, height: 11)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                        .frame(width: 60, height: 9)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
        }
    }
}
