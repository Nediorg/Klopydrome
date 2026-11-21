import AppKit
import NavidromeClient
import SwiftUI

enum AlbumInfoTab: String, CaseIterable, Identifiable {
    case details
    case discs
    case contributors

    var id: String { rawValue }

    var title: String {
        switch self {
        case .details: return "Details".localized
        case .discs: return "Discs".localized
        case .contributors: return "Contributors".localized
        }
    }
}

struct AlbumInfoSheet: View {
    let album: SubsonicAlbum
    let detail: AlbumDetail
    let songs: [SubsonicSong]
    var onDismiss: (() -> Void)?

    @Environment(AppState.self) var app
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: AlbumInfoTab = .details

    func close() {
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }

    var body: some View {
        let tabs = Self.availableTabs(for: detail, songs: songs)
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)

            if tabs.count > 1 {
                Picker("", selection: $selectedTab) {
                    ForEach(tabs) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 24)
                .padding(.bottom, 14)
            }

            Divider()

            Group {
                switch selectedTab {
                case .details:
                    detailsTab
                case .discs:
                    discsTab
                case .contributors:
                    contributorsTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .frame(width: 520, height: 490)
    }
}

// MARK: - Data & Pure Calculations

extension AlbumInfoSheet {
    var albumTitle: String {
        detail.displayName.isEmpty ? album.displayName : detail.displayName
    }

    var artistName: String {
        detail.displayArtist ?? detail.artist ?? album.artist ?? "Unknown Artist".localized
    }

    var isExplicit: Bool {
        album.isExplicit || detail.isExplicit || songs.contains(where: \.isExplicit)
    }

    var totalDurationSeconds: Int {
        let dur = detail.duration ?? 0
        if dur > 0 { return dur }
        return songs.reduce(0) { $0 + ($1.duration ?? 0) }
    }

    var totalSongCount: Int {
        detail.songCount ?? songs.count
    }

    var totalPlays: Int {
        let plays = detail.playCount ?? 0
        if plays > 0 { return plays }
        return songs.reduce(0) { $0 + ($1.playCount ?? 0) }
    }

    var groupedDiscs: [(disc: Int, songs: [SubsonicSong])] {
        Self.groupDiscs(songs)
    }

    var uniqueComposers: [String] {
        Self.extractComposers(from: songs)
    }

    var contributorsByRole: [(role: String, artists: [String])] {
        Self.extractContributors(from: songs)
    }

    var headerTertiaryLine: String? {
        var parts: [String] = []
        if let releaseType = detail.formattedReleaseType {
            parts.append(releaseType)
        }
        if let year = detail.year {
            parts.append(String(year))
        }
        if let genre = detail.genre, !genre.isEmpty {
            parts.append(genre)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func groupDiscs(_ songs: [SubsonicSong]) -> [(disc: Int, songs: [SubsonicSong])] {
        let grouped = Dictionary(grouping: songs, by: { $0.discNumber ?? 1 })
        return grouped.keys.sorted().map { (disc: $0, songs: grouped[$0]!) }
    }

    static func extractComposers(from songs: [SubsonicSong]) -> [String] {
        let all = songs.compactMap(\.resolvedComposer)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        return all.filter { seen.insert($0).inserted }
    }

    static func extractContributors(from songs: [SubsonicSong]) -> [(role: String, artists: [String])] {
        var map: [String: [String]] = [:]
        for song in songs {
            guard let contribs = song.contributors else { continue }
            for contrib in contribs {
                let role = contrib.role.capitalized
                let name = contrib.artist.name
                if !map[role, default: []].contains(name) {
                    map[role, default: []].append(name)
                }
            }
        }
        return map.keys.sorted().map { (role: $0, artists: map[$0]!) }
    }

    static func availableTabs(for detail: AlbumDetail, songs: [SubsonicSong]) -> [AlbumInfoTab] {
        var tabs: [AlbumInfoTab] = [.details]
        let discs = groupDiscs(songs)
        if discs.count > 1 || (detail.discTitles?.isEmpty == false) {
            tabs.append(.discs)
        }
        if !extractComposers(from: songs).isEmpty || !extractContributors(from: songs).isEmpty {
            tabs.append(.contributors)
        }
        return tabs
    }
}

// MARK: - Subviews

extension AlbumInfoSheet {
    var header: some View {
        HStack(spacing: 16) {
            QuickLookCover(
                coverArt: album.coverArt,
                size: 64,
                cornerRadius: 6,
                shadow: false,
                title: albumTitle
            )
            .frame(width: 64, height: 64)
            .help("Quick Look artwork".localized)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(albumTitle)
                        .font(.title3.bold())
                        .lineLimit(1)
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
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)

                if let tertiary = headerTertiaryLine {
                    Text(tertiary)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
    }

    var detailsTab: some View {
        ScrollView {
            VStack(spacing: 12) {
                metaRow("Album".localized, value: albumTitle)
                metaRow("Artist".localized, value: artistName)
                if let version = detail.version, !version.isEmpty {
                    metaRow("Release".localized, value: version)
                }
                if let releaseType = detail.formattedReleaseType {
                    metaRow("Release Type".localized, value: releaseType)
                }
                metaRow("Year".localized, value: detail.year.map(String.init))
                metaRow("Genre".localized, value: detail.genre)
                if let label = detail.recordType, !label.isEmpty, label != detail.formattedReleaseType {
                    metaRow("Record Label".localized, value: label)
                }
                metaRow("Tracks".localized, value: "\(totalSongCount) \(Pluralized.song(totalSongCount))")
                if totalDurationSeconds > 0 {
                    metaRow("Duration".localized, value: Player.format(seconds: Double(totalDurationSeconds)))
                }
                if totalPlays > 0 {
                    metaRow("Plays".localized, value: "\(totalPlays)")
                }
                if let created = detail.created {
                    metaRow("Added".localized, value: SubsonicDate.longDate(created))
                }
            }
            .padding(.top, 4)
        }
    }

    var discsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(groupedDiscs, id: \.disc) { item in
                    discSection(item)
                }
            }
            .padding(.top, 4)
            .padding(.horizontal, 4)
        }
    }

    private func discSection(_ item: (disc: Int, songs: [SubsonicSong])) -> some View {
        let subtitle = detail.discTitle(for: item.disc)
        let count = item.songs.count
        let headerTitle: String = {
            if let subtitle, !subtitle.isEmpty {
                return String(format: "Disc %d: \"%@\" (%d tracks)".localized, item.disc, subtitle, count)
            } else {
                return String(format: "Disc %d (%d tracks)".localized, item.disc, count)
            }
        }()
        let discDuration = item.songs.reduce(0) { $0 + ($1.duration ?? 0) }

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(headerTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if discDuration > 0 {
                    Text(Player.format(seconds: Double(discDuration)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AMColor.secondaryText)
                }
            }

            Divider()

            VStack(spacing: 4) {
                ForEach(item.songs) { song in
                    HStack(spacing: 10) {
                        Text(song.track.map(String.init) ?? "—")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(AMColor.secondaryText)
                            .frame(width: 24, alignment: .trailing)
                        Text(song.displayTitle)
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if let dur = song.duration {
                            Text(Player.format(seconds: Double(dur)))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(AMColor.secondaryText)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    var contributorsTab: some View {
        ScrollView {
            VStack(spacing: 12) {
                if !uniqueComposers.isEmpty {
                    metaRow("Composer".localized, value: uniqueComposers.joined(separator: ", "))
                }
                ForEach(contributorsByRole, id: \.role) { item in
                    metaRow(item.role, value: item.artists.joined(separator: ", "))
                }
            }
            .padding(.top, 4)
        }
    }

    private func metaRow(_ label: String, value: String?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .trailing)
            Text(value ?? "—")
                .font(.callout)
                .foregroundStyle(value == nil ? .tertiary : .primary)
                .textSelection(.enabled)
            Spacer()
        }
    }

    var footer: some View {
        HStack {
            Spacer()
            Button("Done".localized) {
                close()
            }
            .keyboardShortcut(.defaultAction)
        }
    }
}
