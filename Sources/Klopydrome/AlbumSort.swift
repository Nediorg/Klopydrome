import Foundation
import NavidromeClient

/// Sort options for the artist page album shelf/grid.
enum ArtistAlbumSort: String, CaseIterable, Identifiable {
    case release, name, popularity, recentlyAdded, artist, duration, playCount, genre, favorite, id
    var id: String { rawValue }
    var label: String {
        switch self {
        case .release: return "По дате релиза"
        case .name: return "По названию"
        case .popularity: return "По популярности"
        case .recentlyAdded: return "По дате добавления"
        case .artist: return "По исполнителю"
        case .duration: return "По длительности"
        case .playCount: return "По прослушиваниям"
        case .genre: return "По жанру"
        case .favorite: return "По избранным"
        case .id: return "По ID"
        }
    }
}

// Applies the chosen album sort and direction to a raw album list.
// swiftlint:disable:next cyclomatic_complexity
func sortedAlbums(_ source: [SubsonicAlbum], by sort: ArtistAlbumSort, descending: Bool) -> [SubsonicAlbum] {
    switch sort {
    case .release:
        // Unknown-year albums always sort last, in either direction.
        return source.sorted { lhs, rhs in
            switch (lhs.year, rhs.year) {
            case let (lhsYear?, rhsYear?):
                if lhsYear != rhsYear { return descending ? lhsYear > rhsYear : lhsYear < rhsYear }
                return nameAscending(lhs, rhs)
            case (nil, nil): return nameAscending(lhs, rhs)
            case (nil, _): return false
            case (_, nil): return true
            }
        }
    case .name:
        return source.sorted { descending ? nameDescending($0, $1) : nameAscending($0, $1) }
    case .popularity, .playCount:
        return source.sorted { optionalInt(descending, $0.playCount, $1.playCount, lhsAlbum: $0, rhsAlbum: $1) }
    case .recentlyAdded:
        return source.sorted { optionalString(descending, $0.created, $1.created, lhsAlbum: $0, rhsAlbum: $1) }
    case .artist:
        return source.sorted {
            let order = ($0.artist ?? "").localizedCaseInsensitiveCompare($1.artist ?? "")
            return descending ? order == .orderedDescending : order == .orderedAscending
        }
    case .duration:
        return source.sorted { optionalInt(descending, $0.duration, $1.duration, lhsAlbum: $0, rhsAlbum: $1) }
    case .genre:
        return source.sorted {
            let order = ($0.genre ?? "").localizedCaseInsensitiveCompare($1.genre ?? "")
            return descending ? order == .orderedDescending : order == .orderedAscending
        }
    case .favorite:
        return source.sorted { lhs, rhs in
            let lhsStarred = lhs.starred != nil
            let rhsStarred = rhs.starred != nil
            if lhsStarred != rhsStarred { return descending ? lhsStarred : rhsStarred }
            return nameAscending(lhs, rhs)
        }
    case .id:
        return source.sorted { descending ? $0.id > $1.id : $0.id < $1.id }
    }
}

/// Optional-number comparison: values compare in the chosen direction, nil
/// sorts last, ties fall back to the album name.
private func optionalInt(_ descending: Bool, _ lhs: Int?, _ rhs: Int?,
                         lhsAlbum: SubsonicAlbum, rhsAlbum: SubsonicAlbum) -> Bool {
    switch (lhs, rhs) {
    case let (lhsValue?, rhsValue?):
        if lhsValue != rhsValue { return descending ? lhsValue > rhsValue : lhsValue < rhsValue }
        return nameAscending(lhsAlbum, rhsAlbum)
    case (nil, nil): return nameAscending(lhsAlbum, rhsAlbum)
    case (nil, _): return false
    case (_, nil): return true
    }
}

/// Same as `optionalInt`, for ISO-8601 date strings (lexicographic order).
private func optionalString(_ descending: Bool, _ lhs: String?, _ rhs: String?,
                            lhsAlbum: SubsonicAlbum, rhsAlbum: SubsonicAlbum) -> Bool {
    switch (lhs, rhs) {
    case let (lhsValue?, rhsValue?):
        if lhsValue != rhsValue { return descending ? lhsValue > rhsValue : lhsValue < rhsValue }
        return nameAscending(lhsAlbum, rhsAlbum)
    case (nil, nil): return nameAscending(lhsAlbum, rhsAlbum)
    case (nil, _): return false
    case (_, nil): return true
    }
}

private func nameAscending(_ lhs: SubsonicAlbum, _ rhs: SubsonicAlbum) -> Bool {
    lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
}

private func nameDescending(_ lhs: SubsonicAlbum, _ rhs: SubsonicAlbum) -> Bool {
    lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedDescending
}
