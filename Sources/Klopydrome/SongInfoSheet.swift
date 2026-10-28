import SwiftUI
import NavidromeClient

struct SongInfoSheet: View {
    let song: SubsonicSong
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

    @State private var selectedTab: Tab = .details
    @State private var copiedPath = false
    @State private var lyricsLines: [String] = []
    @State private var isLoadingLyrics = false
    @State private var lyricsLoaded = false

    private enum Tab: String, CaseIterable, Identifiable {
        case details
        case file
        case lyrics

        var id: String { rawValue }

        var title: String {
            switch self {
            case .details: return "Details".localized
            case .file: return "File".localized
            case .lyrics: return "Lyrics".localized
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)

            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.bottom, 14)

            Divider()

            Group {
                switch selectedTab {
                case .details:
                    detailsTab
                case .file:
                    fileTab
                case .lyrics:
                    lyricsTab
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
        .frame(width: 500, height: 490)
    }

    private var header: some View {
        HStack(spacing: 16) {
            QuickLookCover(
                coverArt: song.coverArt,
                size: 64,
                cornerRadius: 6,
                shadow: false,
                title: song.album ?? song.displayTitle
            )
            .frame(width: 64, height: 64)
                .help("Quick Look artwork".localized)

            VStack(alignment: .leading, spacing: 3) {
                Text(song.displayTitle)
                    .font(.title3.bold())
                    .lineLimit(1)
                if let artist = song.artist {
                    Text(artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let album = song.album {
                    Text(album)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
    }

    private var detailsTab: some View {
        ScrollView {
            VStack(spacing: 12) {
                metaRow("Title".localized, value: song.displayTitle)
                metaRow("Artist".localized, value: song.artist)
                metaRow("Album".localized, value: song.album)
                metaRow("Album artist".localized, value: song.albumArtist)
                metaRow("Composer".localized, value: song.composer)
                metaRow("Genre".localized, value: song.genre)
                metaRow("Year".localized, value: song.year.map(String.init))
                metaRow("Track Number".localized, value: song.track.map(String.init))
                metaRow("Disc".localized, value: song.discNumber.map(String.init))
                HStack(alignment: .top) {
                    Text("Rating".localized)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(width: 140, alignment: .trailing)
                    RatingStars(song: song, app: app, size: 12, spacing: 3)
                    Spacer()
                }
            }
            .padding(.top, 4)
        }
    }

    private var fileTab: some View {
        ScrollView {
            VStack(spacing: 12) {
                metaRow("Format".localized, value: song.suffix?.uppercased())
                metaRow("Bitrate".localized, value: song.bitRate.map { "\($0) kbps" })
                metaRow("Duration".localized, value: song.duration.map { Player.format(seconds: Double($0)) })
                metaRow("Size".localized, value: song.size.map {
                    ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file)
                })
                metaRow("Added".localized, value: SubsonicDate.longDate(song.created))
                metaRow("Plays".localized, value: song.playCount.map(String.init) ?? "0")
                if let path = song.path {
                    HStack(alignment: .top, spacing: 8) {
                        Text("Location".localized)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(width: 140, alignment: .trailing)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(path)
                                .font(.caption.monospaced())
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(path, forType: .string)
                                copiedPath = true
                            } label: {
                                Label(copiedPath ? "Path Copied".localized : "Copy Path".localized,
                                      systemImage: copiedPath ? "checkmark" : "doc.on.doc")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(AMColor.accent)
                        }
                        Spacer()
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private var lyricsTab: some View {
        Group {
            if isLoadingLyrics {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !lyricsLines.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(lyricsLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            } else {
                ContentUnavailableView("No lyrics available".localized,
                                       systemImage: "quote.bubble",
                                       description: Text("No lyrics found on the server for this song.".localized))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: song.id) {
            await fetchLyrics()
        }
    }

    private func fetchLyrics() async {
        guard !lyricsLoaded else { return }
        isLoadingLyrics = true
        defer {
            isLoadingLyrics = false
            lyricsLoaded = true
        }

        if app.lyrics.loadedForSongID == song.id {
            if !app.lyrics.syncedLines.isEmpty {
                lyricsLines = app.lyrics.syncedLines.compactMap(\.value)
                return
            } else if let plain = app.lyrics.plainText, !plain.isEmpty {
                lyricsLines = plain.components(separatedBy: "\n")
                return
            }
        }

        guard let client = app.client else { return }
        if let entries = try? await client.getLyricsBySongId(id: song.id) {
            if let timed = entries.first(where: { $0.synced ?? false }),
               let lines = timed.line, !lines.isEmpty {
                lyricsLines = lines.compactMap(\.value)
                return
            }
            if let plain = LyricsStore.plainText(from: entries), !plain.isEmpty {
                lyricsLines = plain.components(separatedBy: "\n")
                return
            }
        }

        if let fallback = try? await client.getLyrics(artist: song.artist ?? "", title: song.title ?? ""),
           let text = fallback.value, !text.isEmpty {
            let timed = LrcTextParser.parse(text)
            if !timed.isEmpty {
                lyricsLines = timed.compactMap(\.value)
            } else {
                lyricsLines = text.components(separatedBy: "\n")
            }
        }
    }

    private func metaRow(_ label: String, value: String?) -> some View {
        HStack(alignment: .top, spacing: 8) {
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

    private var footer: some View {
        HStack {
            Spacer()
            Button("Done".localized) {
                close()
            }
            .keyboardShortcut(.defaultAction)
        }
    }
}

extension AppState {
    func inspectSong(_ song: SubsonicSong) {
        inspectingSong = song
        if MiniPlayerPanelController.shared.isPanelActive {
            MiniPlayerPanelController.shared.closeForLibraryNavigation()
        }
    }
}
