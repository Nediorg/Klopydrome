import Foundation
import NavidromeClient

/// A locally-stored, rule-based playlist. Subsonic/Navidrome can't store these
/// server-side, so they live in UserDefaults and their tracks are recomputed on
/// demand from the server.
struct SmartPlaylist: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    /// Genre to match (exact, case-insensitive). nil/empty = all genres.
    var genre: String?
    /// Only songs the user has starred (favorited).
    var starredOnly = false
    /// Only songs played at least this many times. nil = any.
    var minPlayCount: Int?
    /// Only songs rated at least this many stars (1...5). nil = any.
    var minRating: Int?
    /// Maximum number of tracks to include. nil = no limit (all matches).
    var limit: Int?
    /// Randomize the resulting order instead of sorting by title.
    var shuffleOrder = false
    /// Optional full query-tree (the DSL AST), set by the visual rule editor.
    /// When present it takes precedence over the legacy single-field rules above.
    var query: SmartQuery?

    var trimmedGenre: String? {
        guard let genre = genre?.trimmingCharacters(in: .whitespaces), !genre.isEmpty else { return nil }
        return genre
    }

    /// True if the playlist uses the full query-tree editor (not legacy fields).
    var hasQueryRules: Bool { query != nil }

    func matches(_ song: SubsonicSong) -> Bool {
        if let query { return query.matches(song) }
        if let genre = trimmedGenre {
            guard song.genre?.caseInsensitiveCompare(genre) == .orderedSame else { return false }
        }
        if starredOnly, song.starred?.isEmpty ?? true { return false }
        if let minPlayCount, (song.playCount ?? 0) < minPlayCount { return false }
        if let minRating {
            let rating = song.userRating ?? Int(song.averageRating?.rounded() ?? 0)
            if rating < minRating { return false }
        }
        return true
    }

    /// Human-readable description of the rules, for list rows and detail headers.
    var ruleSummary: String {
        if let query {
            let expr = query.root
            if expr.isGroup, let logic = expr.groupLogic, !expr.children.isEmpty {
                let head = expr.children.prefix(3).map { $0.shortSummary }.joined(separator: ", ")
                let extra = expr.children.count > 3 ? ", …" : ""
                let formatKey = logic == .all
                    ? "format.smartPlaylist.all"
                    : "format.smartPlaylist.any"
                return L10n.format(formatKey, "\(head)\(extra)")
            }
            return L10n.text("Вся музыка")
        }
        var parts: [String] = []
        if let trimmedGenre { parts.append(L10n.format("format.genre", trimmedGenre)) }
        if starredOnly { parts.append(L10n.text("Только избранное")) }
        if let minPlayCount { parts.append(L10n.format("format.smartPlaylist.playCount", minPlayCount)) }
        if let minRating { parts.append(L10n.format("format.smartPlaylist.rating", minRating)) }
        if shuffleOrder { parts.append(L10n.text("Перемешивать")) }
        return parts.isEmpty ? L10n.text("Вся музыка") : parts.joined(separator: " · ")
    }
}

extension QueryExpr {
    /// A short, human-readable description used in playlist tiles.
    var shortSummary: String {
        if isGroup, let logic = groupLogic {
            let joined = children.prefix(2).map { $0.shortSummary }.joined(separator: " · ")
            return L10n.format(logic == .all ? "format.smartPlaylist.and" : "format.smartPlaylist.or", joined)
        }
        guard let op, let field, let value else { return "—" }
        let fieldLabel = QueryField(dsl: field)?.label ?? field
        return "\(fieldLabel) \(op.label) \(value.displayText)"
    }
}
