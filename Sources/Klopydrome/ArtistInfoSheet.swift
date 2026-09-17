import AppKit
import NavidromeClient
import SwiftUI

/// Modal sheet displaying complete artist details, discography statistics,
/// genres, active years, and biography from the server.
struct ArtistInfoSheet: View {
    let artist: Artist
    let detail: ArtistDetail
    let roleLabel: String?
    let albums: [SubsonicAlbum]
    let allSongs: [SubsonicSong]
    let artistInfo: ArtistInfoPayload?
    var onDismiss: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    private func close() {
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }

    private var artistName: String {
        detail.name ?? artist.name
    }

    private var yearsRange: String? {
        let years = (albums.compactMap(\.year) + allSongs.compactMap(\.year)).filter { $0 > 0 }
        guard let minYear = years.min(), let maxYear = years.max() else { return nil }
        if minYear == maxYear { return "\(minYear)" }
        return "\(minYear) — \(maxYear)"
    }

    private var allGenres: [String] {
        let set = Set(albums.compactMap(\.genre) + allSongs.compactMap(\.genre))
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return Array(set).sorted()
    }

    private var totalDurationSeconds: Int {
        allSongs.reduce(0) { $0 + ($1.duration ?? 0) }
    }

    private var totalPlays: Int {
        allSongs.reduce(0) { $0 + ($1.playCount ?? 0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    heroProfile
                    statisticsSection
                    if !allGenres.isEmpty {
                        genresSection
                    }
                    if let bio = artistInfo?.biography, !bio.isEmpty {
                        biographySection(bio)
                    }
                    linksSection
                }
                .padding(24)
            }
        }
        .frame(width: 500, height: 560)
    }

    // MARK: Header Bar

    private var headerBar: some View {
        HStack {
            Text("Сведения об исполнителе".localized)
                .font(.headline)
            Spacer()
            Button {
                close()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Закрыть".localized)
            .accessibilityLabel("Закрыть".localized)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: Profile

    private var heroProfile: some View {
        HStack(spacing: 16) {
            CircularArtistArt(name: artistName, imageURL: detail.artistImageUrl ?? artist.artistImageUrl, size: 64)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))

            VStack(alignment: .leading, spacing: 4) {
                Text(artistName)
                    .font(.title2.bold())
                Text(roleLabel ?? "Исполнитель".localized)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Statistics

    private var statisticsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Медиатека".localized)
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            VStack(spacing: 14) {
                HStack(spacing: 16) {
                    statTile(label: "Альбомы".localized, value: "\(albums.count)")
                    statTile(label: "Песни".localized, value: "\(allSongs.count)")
                    if totalDurationSeconds > 0 {
                        let duration = Player.format(seconds: Double(totalDurationSeconds))
                        statTile(label: "Длительность".localized, value: duration)
                    }
                }

                if yearsRange != nil || totalPlays > 0 {
                    HStack(spacing: 16) {
                        if let yearsRange {
                            statTile(label: "Годы активности".localized, value: yearsRange)
                        }
                        if totalPlays > 0 {
                            statTile(label: "Прослушиваний".localized, value: "\(totalPlays)")
                        }
                    }
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(AMColor.surfaceLight))
        }
    }

    private func statTile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Genres

    private var genresSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Жанры".localized)
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 6) {
                ForEach(allGenres, id: \.self) { genre in
                    Text(genre)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(AMColor.surfaceLight))
                }
            }
        }
    }

    // MARK: Biography

    private func biographySection(_ bio: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Биография".localized)
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            Text(cleanBiography(bio))
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineSpacing(3)
        }
    }

    private func cleanBiography(_ raw: String) -> LocalizedStringKey {
        var text = raw
        if let lastFm = artistInfo?.lastFmUrl, !lastFm.isEmpty {
            text = text.replacingOccurrences(
                of: "<a href=\"[^\"]+\">Read more on Last.fm</a>",
                with: "[Read more on Last.fm](\(lastFm))",
                options: .regularExpression
            )
            text = text.replacingOccurrences(
                of: "Read more on Last.fm",
                with: "[Read more on Last.fm](\(lastFm))"
            )
        }
        // Strip remaining HTML tags
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return LocalizedStringKey(text)
    }

    // MARK: Links

    private var linksSection: some View {
        HStack(spacing: 12) {
            if let lastFm = artistInfo?.lastFmUrl, let url = URL(string: lastFm) {
                Link(destination: url) {
                    Label("Last.fm", systemImage: "arrow.up.right.square")
                        .font(.caption)
                }
            }
            if let mbz = artistInfo?.musicBrainzId, !mbz.isEmpty {
                Text("MusicBrainz: \(mbz)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
        }
    }
}

/// Simple flow layout container for capsule tags.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        var height: CGFloat = 0
        var currentX: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > width, currentX > 0 {
                currentX = 0
                height += rowHeight + spacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            currentX += size.width + spacing
        }
        height += rowHeight
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX, currentX > bounds.minX {
                currentX = bounds.minX
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: .unspecified)
            rowHeight = max(rowHeight, size.height)
            currentX += size.width + spacing
        }
    }
}
