import SwiftUI

// MARK: - Skeleton Kit

/// Canonical building blocks for loading skeleton placeholders across Klopydrome.
/// Guarantees exact layout metrics, unified visual tokens, and strict masking
/// so shimmering light bands never bleed onto transparent margins or spacing.

/// A single skeleton row matching the exact layout and 46pt height of `SongRow`.
struct SkeletonSongRow: View {
    var showAlbum: Bool = true
    var forMask: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Color.clear
                .frame(width: 16, height: 16)

            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    if showAlbum {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(forMask ? Color.black : Color.primary.opacity(0.06))
                            .frame(width: 36, height: 36)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(forMask ? Color.black : Color.primary.opacity(0.07))
                            .frame(width: 160, height: 12)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(forMask ? Color.black : Color.primary.opacity(0.05))
                            .frame(width: 110, height: 10)
                    }
                }

                Spacer(minLength: 8)

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(forMask ? Color.black : Color.primary.opacity(0.04))
                    .frame(width: 36, height: 10)
            }
            .padding(.leading, 5)
            .padding(.trailing, 8)
            .padding(.vertical, 5)
        }
        .frame(height: 46)
    }
}

/// A vertical list of skeleton song rows with a single cohesive shimmer sweep.
struct SkeletonSongList: View {
    var count: Int = 10
    var showAlbum: Bool = true

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
                SkeletonSongRow(showAlbum: showAlbum, forMask: forMask)
            }
        }
    }
}

/// A card skeleton for album grid items or circular artist avatars.
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

/// A horizontally scrolling shelf of card skeletons with a single cohesive shimmer.
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

/// A 3-row compact column matching Apple Music style compact song blocks (e.g. `CompactSongColumn`).
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
