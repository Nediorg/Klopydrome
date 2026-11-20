import Foundation
import NavidromeClient

enum PlaylistTrackSort: String, CaseIterable, Identifiable {
    case playlistOrder = "Playlist Order"
    case title = "Title"
    case artist = "Artist"
    case album = "Album"
    case duration = "Duration"
    case rating = "Rating"
    case playCount = "Plays"
    case added = "Date Added"

    var id: String { rawValue }

    var label: String { rawValue }
}

struct PlaylistIndexedSong: Identifiable {
    let displayIndex: Int
    let playlistIndex: Int
    let song: SubsonicSong
    let id: String
}

struct PlaylistFeaturedArtist: Identifiable {
    let id: String
    let name: String
    let coverArt: String?
    let trackCount: Int
}
