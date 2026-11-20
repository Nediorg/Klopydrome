import AppKit
import NavidromeClient
import SwiftUI

struct AlbumInfoSheet: View {
    let album: SubsonicAlbum
    let detail: AlbumDetail
    let songs: [SubsonicSong]
    var onDismiss: (() -> Void)?

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    private func close() {
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }

    private var albumTitle: String {
        detail.displayName.isEmpty ? album.displayName : detail.displayName
    }

    private var artistName: String {
        detail.displayArtist ?? detail.artist ?? album.artist ?? "Unknown Artist".localized
    }

    private var isExplicit: Bool {
        album.isExplicit || detail.isExplicit || songs.contains(where: \.isExplicit)
    }

    private var totalDurationSeconds: Int {
        let dur = detail.duration ?? 0
        if dur > 0 { return dur }
        return songs.reduce(0) { $0 + ($1.duration ?? 0) }
    }

    private var totalSongCount: Int {
        detail.songCount ?? songs.count
    }

    private var totalPlays: Int {
        let plays = detail.playCount ?? 0
        if plays > 0 { return plays }
        return songs.reduce(0) { $0 + ($1.playCount ?? 0) }
    }

    private var groupedDiscs: [(disc: Int, songs: [SubsonicSong])] {
        let grouped = Dictionary(grouping: songs, by: { $0.discNumber ?? 1 })
        return grouped.keys.sorted().map { (disc: $0, songs: grouped[$0]!) }
    }

    private var uniqueComposers: [String] {
        let all = songs.compactMap(\.resolvedComposer)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        return all.filter { seen.insert($0).inserted }
    }

    private var contributorsByRole: [(role: String, artists: [String])] {
        var map: [String: [String]] = [:]
        for song in songs {
            guard let contribs = song.contributors else { continue }
            for c in contribs {
                let role = c.role.capitalized
                let name = c.artist.name
                if !map[role, default: []].contains(name) {
                    map[role, default: []].append(name)
                }
            }
        }
        return map.keys.sorted().map { (role: $0, artists: map[$0]!) }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    heroProfile
                    statisticsSection
                    metadataSection
                    if groupedDiscs.count > 1 || (detail.discTitles?.isEmpty == false) {
                        discsSection
                    }
                    if !uniqueComposers.isEmpty || !contributorsByRole.isEmpty {
                        contributorsSection
                    }
                }
                .padding(24)
            }
        }
        .frame(width: 500, height: 560)
    }

    private var headerBar: some View {
        HStack {
            Text("Album Information".localized)
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
            .help("Close".localized)
            .accessibilityLabel("Close".localized)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var heroProfile: some View {
        HStack(spacing: 16) {
            QuickLookCover(
                coverArt: album.coverArt,
                size: 72,
                cornerRadius: 6,
                shadow: false,
                title: albumTitle
            )
            .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(albumTitle)
                        .font(.title2.bold())
                        .lineLimit(2)
                    if isExplicit {
                        ExplicitBadge(size: 13)
                    }
                }

                Button {
                    close()
                    if let artistId = detail.artistId ?? album.artistId {
                        app.openArtistInLibrary(Artist(id: artistId, name: artistName))
                    }
                } label: {
                    Text(artistName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AMColor.accent)
                }
                .buttonStyle(.plain)

                if let version = detail.version, !version.isEmpty {
                    Text(version)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var statisticsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Library".localized)
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                statTile(label: "Tracks".localized, value: "\(totalSongCount)")
                if totalDurationSeconds > 0 {
                    let duration = Player.format(seconds: Double(totalDurationSeconds))
                    statTile(label: "Duration".localized, value: duration)
                }
                if totalPlays > 0 {
                    statTile(label: "Plays".localized, value: "\(totalPlays)")
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(AMColor.surfaceLight))
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Release".localized)
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                if let releaseType = detail.formattedReleaseType {
                    metaRow("Release Type".localized, value: releaseType)
                }
                if let year = detail.year {
                    metaRow("Year".localized, value: String(year))
                }
                if let genre = detail.genre, !genre.isEmpty {
                    metaRow("Genre".localized, value: genre)
                }
                if let label = detail.recordType, !label.isEmpty, label != detail.formattedReleaseType {
                    metaRow("Record Label".localized, value: label)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(AMColor.surfaceLight))
        }
    }

    private var discsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Discs".localized)
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(groupedDiscs, id: \.disc) { item in
                    let subtitle = detail.discTitle(for: item.disc)
                    let count = item.songs.count
                    let label: String = {
                        if let subtitle, !subtitle.isEmpty {
                            return String(format: "Disc %d: \"%@\" (%d tracks)".localized, item.disc, subtitle, count)
                        } else {
                            return String(format: "Disc %d (%d tracks)".localized, item.disc, count)
                        }
                    }()

                    HStack(spacing: 10) {
                        Image(systemName: "opticaldisc")
                            .font(.system(size: 13))
                            .foregroundStyle(AMColor.accent)
                        Text(label)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(AMColor.surfaceLight))
        }
    }

    private var contributorsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Contributors".localized)
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                if !uniqueComposers.isEmpty {
                    metaRow("Composer".localized, value: uniqueComposers.joined(separator: ", "))
                }
                ForEach(contributorsByRole, id: \.role) { item in
                    metaRow(item.role, value: item.artists.joined(separator: ", "))
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

    private func metaRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
