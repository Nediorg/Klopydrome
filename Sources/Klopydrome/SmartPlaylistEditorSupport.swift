import SwiftUI
import UniformTypeIdentifiers

struct QueryDrag: Codable, Transferable, Hashable {
    let nodeID: UUID
    var isGroup: Bool
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}

enum SmartSort: String, CaseIterable {
    case title, artist, album, year, duration, playCount, rating, random

    var label: String {
        switch self {
        case .title: return "By Title"
        case .artist: return "By Artist"
        case .album: return "By Album"
        case .year: return "By Year"
        case .duration: return "By Duration"
        case .playCount: return "By Play Count"
        case .rating: return "By Rating"
        case .random: return "Random"
        }
    }

    var json: String {
        switch self {
        case .title: return "title"
        case .artist: return "artist"
        case .album: return "album"
        case .year: return "year"
        case .duration: return "duration"
        case .playCount: return "playcount"
        case .rating: return "rating"
        case .random: return "random"
        }
    }

    func json(descending: Bool) -> String {
        if self == .random { return json }
        return (descending ? "-" : "") + json
    }

    init?(json: String?) {
        guard let json else { return nil }
        let key = Self.strippedKey(json).lowercased()
        guard let parsed = Self.allCases.first(where: { $0.json == key }) else { return nil }
        self = parsed
    }

    private static func strippedKey(_ json: String) -> String {
        json.first == "-" || json.first == "+" ? String(json.dropFirst()) : json
    }
}

extension SmartPlaylistEditorView {
    var previewContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("View".localized)
                    .font(.headline)
                if case .loaded(let songs) = previewState, !songs.isEmpty {
                    Text(L10n.format("format.smartPlaylist.songs", songs.count))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            Divider()
            switch previewState {
            case .idle, .loading:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Failed to load".localized, systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Retry".localized) { preview() }
                }
            case .loaded(let songs) where songs.isEmpty:
                ContentUnavailableView {
                    Label("No Matches".localized, systemImage: "music.note.list")
                } description: {
                    Text("No songs match the current rules.".localized)
                }
            case .loaded(let songs):
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                            QueueTrackRow(
                                song: song,
                                isCurrent: app.player.currentSong?.id == song.id,
                                showDivider: index < songs.count - 1
                            ) {
                                app.play(songs, at: index)
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 520, height: 420)
    }

    func dismissModal() {
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }
}
