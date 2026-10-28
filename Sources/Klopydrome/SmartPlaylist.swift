import Foundation
import NavidromeClient

struct SmartPlaylist: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var genre: String?
    var starredOnly = false
    var minPlayCount: Int?
    var minRating: Int?
    var limit: Int?
    var shuffleOrder = false
    var query: SmartQuery?

    var trimmedGenre: String? {
        guard let genre = genre?.trimmingCharacters(in: .whitespaces), !genre.isEmpty else { return nil }
        return genre
    }

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
            return "All Music".localized
        }
        var parts: [String] = []
        if let trimmedGenre { parts.append(L10n.format("format.genre", trimmedGenre)) }
        if starredOnly { parts.append("Favorites only".localized) }
        if let minPlayCount { parts.append(L10n.format("format.smartPlaylist.playCount", minPlayCount)) }
        if let minRating { parts.append(L10n.format("format.smartPlaylist.rating", minRating)) }
        if shuffleOrder { parts.append("Shuffle".localized) }
        return parts.isEmpty ? "All Music".localized : parts.joined(separator: " · ")
    }
}

extension QueryExpr {
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
