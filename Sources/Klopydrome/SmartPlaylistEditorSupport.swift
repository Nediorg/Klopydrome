import SwiftUI
import UniformTypeIdentifiers

/// Drag payload for moving rule/group nodes between slots in the rule editor.
struct QueryDrag: Codable, Transferable, Hashable {
    let nodeID: UUID
    var isGroup: Bool
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}

// MARK: - Sort options

/// Sort options exposed by the rule editor. `json` is the base server key;
/// the picker direction is emitted as a leading "-" by `json(descending:)`.
/// `random` is a special shuffle pseudo-sort that ignores the direction toggle.
enum SmartSort: String, CaseIterable {
    case title, artist, album, year, duration, playCount, rating, random

    var label: String {
        switch self {
        case .title: return "По названию"
        case .artist: return "По исполнителю"
        case .album: return "По альбому"
        case .year: return "По году"
        case .duration: return "По длительности"
        case .playCount: return "По прослушиваниям"
        case .rating: return "По оценке"
        case .random: return "Случайно"
        }
    }

    /// The server sort-field key without a direction prefix.
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

    /// Direction-aware server sort string (`-year` for descending).
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

    /// Strips a leading `+`/`-` direction prefix so `-year` parses as `.year`.
    private static func strippedKey(_ json: String) -> String {
        json.first == "-" || json.first == "+" ? String(json.dropFirst()) : json
    }
}

// MARK: - Preview popover & dismissal

extension SmartPlaylistEditorView {
    var previewContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Просмотр".localized)
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
                    Label("Не удалось загрузить", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Повторить") { preview() }
                }
            case .loaded(let songs) where songs.isEmpty:
                ContentUnavailableView {
                    Label("Нет совпадений", systemImage: "music.note.list")
                } description: {
                    Text("Ни одна песня не подходит под текущие правила.".localized)
                }
            case .loaded(let songs):
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                            QueueTrackRow(
                                song: song,
                                isCurrent: app.player.currentSong?.id == song.id
                            ) {
                                app.play(songs, at: index)
                            }
                            Divider().padding(.leading, 56)
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
