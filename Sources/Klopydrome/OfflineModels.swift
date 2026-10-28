import Foundation
import SwiftData
import NavidromeClient

public struct MinimalAlbumTrack: Codable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let artist: String?
    public let track: Int?
    public let discNumber: Int?
    public let duration: Int?
    public let suffix: String?
    public let starred: String?
    public let userRating: Int?

    public init(
        id: String,
        title: String,
        artist: String? = nil,
        track: Int? = nil,
        discNumber: Int? = nil,
        duration: Int? = nil,
        suffix: String? = nil,
        starred: String? = nil,
        userRating: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.track = track
        self.discNumber = discNumber
        self.duration = duration
        self.suffix = suffix
        self.starred = starred
        self.userRating = userRating
    }

    public init(from song: SubsonicSong) {
        self.id = song.id
        self.title = song.title ?? song.displayTitle
        self.artist = song.artist
        self.track = song.track
        self.discNumber = song.discNumber
        self.duration = song.duration
        self.suffix = song.suffix
        self.starred = song.starred
        self.userRating = song.userRating
    }

    func toSubsonicSong(album: OfflineAlbum) -> SubsonicSong {
        SubsonicSong(
            id: id,
            parent: album.id,
            title: title,
            album: album.title,
            artist: artist ?? album.artistName,
            track: track,
            year: album.year,
            genre: album.genre,
            coverArt: album.coverArt,
            suffix: suffix,
            duration: duration,
            discNumber: discNumber,
            starred: starred,
            userRating: userRating,
            albumId: album.id,
            artistId: album.artistID,
            albumArtist: album.artistName
        )
    }
}

@Model
final class OfflineArtist {
    @Attribute(.unique) var id: String
    var name: String
    var albumCount: Int?
    var artistImageUrl: String?
    var starred: String?
    var biography: String?
    var updatedAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \OfflineAlbum.artist)
    var albums: [OfflineAlbum] = []

    @Relationship(deleteRule: .nullify, inverse: \OfflineTrack.artist)
    var tracks: [OfflineTrack] = []

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

@Model
final class OfflineAlbum {
    @Attribute(.unique) var id: String
    var title: String
    var artistName: String?
    var artistID: String?
    var coverArt: String?
    var songCount: Int?
    var duration: Int?
    var year: Int?
    var genre: String?
    var starred: String?
    var recordType: String?
    var musicBrainzId: String?
    var created: String?
    var updatedAt: Date = Date()
    var tracksSummaryData: Data?

    var artist: OfflineArtist?

    @Relationship(deleteRule: .nullify, inverse: \OfflineTrack.album)
    var tracks: [OfflineTrack] = []

    init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

@Model
final class OfflineTrack {
    @Attribute(.unique) var id: String
    var title: String
    var albumTitle: String?
    var artistName: String?
    var albumArtistName: String?
    var trackNumber: Int?
    var discNumber: Int?
    var year: Int?
    var genre: String?
    var coverArt: String?
    var size: Int?
    var contentType: String?
    var suffix: String?
    var duration: Int?
    var bitRate: Int?
    var path: String?
    var playCount: Int?
    var starred: String?
    var userRating: Int?
    var averageRating: Double?
    var albumID: String?
    var artistID: String?
    var albumArtistID: String?
    var musicBrainzId: String?
    var cachedAt: Date = Date()
    var isDownloaded: Bool = false

    var album: OfflineAlbum?
    var artist: OfflineArtist?

    @Relationship(deleteRule: .nullify, inverse: \OfflinePlaylistEntry.track)
    var playlistEntries: [OfflinePlaylistEntry] = []

    init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

@Model
final class OfflinePlaylist {
    @Attribute(.unique) var id: String
    var name: String
    var comment: String?
    var owner: String?
    var coverArt: String?
    var songCount: Int?
    var duration: Int?
    var created: String?
    var changed: String?
    var isPublic: Bool?
    var isReadonly: Bool?
    var validUntil: String?
    var updatedAt: Date = Date()
    var tracksSummaryData: Data?

    @Relationship(deleteRule: .cascade, inverse: \OfflinePlaylistEntry.playlist)
    var entries: [OfflinePlaylistEntry] = []

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

@Model
final class OfflinePlaylistEntry {
    @Attribute(.unique) var id: String
    var index: Int
    var trackID: String?
    var fallbackTitle: String?
    var fallbackDuration: Int?
    var fallbackArtist: String?
    var fallbackAlbum: String?
    var fallbackCoverArt: String?
    var fallbackTrackNumber: Int?
    var fallbackDiscNumber: Int?
    var fallbackYear: Int?
    var fallbackGenre: String?

    var playlist: OfflinePlaylist?
    var track: OfflineTrack?

    init(id: String, index: Int) {
        self.id = id
        self.index = index
    }
}
