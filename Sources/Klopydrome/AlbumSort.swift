import Foundation
import NavidromeClient

enum AlbumSort: String, CaseIterable, Hashable, Identifiable {
    case release, name, popularity, recentlyAdded, artist, duration, playCount, genre, favorite, id
    var id: String { rawValue }
    var label: String {
        switch self {
        case .release: return "By Release Date"
        case .name: return "By Name"
        case .popularity: return "By Popularity"
        case .recentlyAdded: return "By Date Added"
        case .artist: return "By Artist"
        case .duration: return "By Duration"
        case .playCount: return "By Play Count"
        case .genre: return "By Genre"
        case .favorite: return "By Favorites"
        case .id: return "By ID"
        }
    }

    var asAlbumListType: AlbumListType? {
        switch self {
        case .name: return .alphabeticalByName
        case .artist: return .alphabeticalByArtist
        case .recentlyAdded: return .newest
        case .popularity, .playCount: return .frequent
        case .favorite: return .starred
        case .release, .duration, .genre, .id: return nil
        }
    }
}

typealias LibrarySort = AlbumSort
typealias ArtistAlbumSort = AlbumSort

func sortedAlbums(_ source: [SubsonicAlbum], by sort: AlbumSort, descending: Bool) -> [SubsonicAlbum] {
    switch sort {
    case .release:
        return source.sorted { compareRelease($0, $1, descending: descending) }
    case .name:
        return source.sorted { descending ? nameDescending($0, $1) : nameAscending($0, $1) }
    case .popularity, .playCount:
        return source.sorted { optionalInt(descending, $0.playCount, $1.playCount, lhsAlbum: $0, rhsAlbum: $1) }
    case .recentlyAdded:
        return source.sorted { optionalString(descending, $0.created, $1.created, lhsAlbum: $0, rhsAlbum: $1) }
    case .artist:
        return source.sorted { compareStringField($0.artist, $1.artist, descending: descending) }
    case .duration:
        return source.sorted { optionalInt(descending, $0.duration, $1.duration, lhsAlbum: $0, rhsAlbum: $1) }
    case .genre:
        return source.sorted { compareStringField($0.genre, $1.genre, descending: descending) }
    case .favorite:
        return source.sorted { compareFavorite($0, $1, descending: descending) }
    case .id:
        return source.sorted { descending ? $0.id > $1.id : $0.id < $1.id }
    }
}

private func compareRelease(_ lhs: SubsonicAlbum, _ rhs: SubsonicAlbum, descending: Bool) -> Bool {
    switch (lhs.year, rhs.year) {
    case let (lhsYear?, rhsYear?):
        if lhsYear != rhsYear { return descending ? lhsYear > rhsYear : lhsYear < rhsYear }
        return nameAscending(lhs, rhs)
    case (nil, nil): return nameAscending(lhs, rhs)
    case (nil, _): return false
    case (_, nil): return true
    }
}

private func compareFavorite(_ lhs: SubsonicAlbum, _ rhs: SubsonicAlbum, descending: Bool) -> Bool {
    let lhsStarred = lhs.starred != nil
    let rhsStarred = rhs.starred != nil
    if lhsStarred != rhsStarred { return descending ? lhsStarred : rhsStarred }
    return nameAscending(lhs, rhs)
}

private func compareStringField(_ lhs: String?, _ rhs: String?, descending: Bool) -> Bool {
    let order = (lhs ?? "").localizedCaseInsensitiveCompare(rhs ?? "")
    return descending ? order == .orderedDescending : order == .orderedAscending
}

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
