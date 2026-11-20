import Foundation

public struct AlbumList: Codable {
    public let album: [SubsonicAlbum]?
    public init(album: [SubsonicAlbum]? = nil) { self.album = album }
}

public struct SongListPayload: Codable {
    public let song: [SubsonicSong]?
    public init(song: [SubsonicSong]? = nil) { self.song = song }
}

public struct GenresPayload: Codable {
    public let genre: [Genre]?
    public init(genre: [Genre]? = nil) { self.genre = genre }
}

public struct SearchResultPayload: Codable {
    public let artist: [Artist]?
    public let album: [SubsonicAlbum]?
    public let song: [SubsonicSong]?
    public init(artist: [Artist]? = nil, album: [SubsonicAlbum]? = nil, song: [SubsonicSong]? = nil) {
        self.artist = artist
        self.album = album
        self.song = song
    }
}

public struct ArtistsPayload: Codable {
    public let ignoredArticles: String?
    public let index: [ArtistIndex]?
    public init(ignoredArticles: String? = nil, index: [ArtistIndex]? = nil) {
        self.ignoredArticles = ignoredArticles
        self.index = index
    }
}

public struct PlaylistsPayload: Codable {
    public let playlist: [PlaylistSummary]?
    public init(playlist: [PlaylistSummary]? = nil) { self.playlist = playlist }
}

public struct PlayQueuePayload: Codable {
    public let id: String?
    public let current: String?
    public let position: Int?
    public let changedBy: String?
    public let changed: String?
    public let entry: [SubsonicSong]?
    public init(id: String? = nil, current: String? = nil, position: Int? = nil,
                changedBy: String? = nil, changed: String? = nil, entry: [SubsonicSong]? = nil) {
        self.id = id
        self.current = current
        self.position = position
        self.changedBy = changedBy
        self.changed = changed
        self.entry = entry
    }
}

public struct AlbumInfoPayload: Codable {
    public let notes: String?
    public let lastFmUrl: String?
    public let musicBrainzId: String?
    public let largeImageUrl: String?
    public let mediumImageUrl: String?
    public let smallImageUrl: String?
    public init(notes: String? = nil, lastFmUrl: String? = nil, musicBrainzId: String? = nil,
                largeImageUrl: String? = nil, mediumImageUrl: String? = nil, smallImageUrl: String? = nil) {
        self.notes = notes
        self.lastFmUrl = lastFmUrl
        self.musicBrainzId = musicBrainzId
        self.largeImageUrl = largeImageUrl
        self.mediumImageUrl = mediumImageUrl
        self.smallImageUrl = smallImageUrl
    }
}

public struct ArtistInfoPayload: Codable, Hashable {
    public let biography: String?
    public let musicBrainzId: String?
    public let lastFmUrl: String?
    public let smallImageUrl: String?
    public let mediumImageUrl: String?
    public let largeImageUrl: String?
    public let similarArtist: [Artist]?

    public init(biography: String? = nil, musicBrainzId: String? = nil, lastFmUrl: String? = nil,
                smallImageUrl: String? = nil, mediumImageUrl: String? = nil, largeImageUrl: String? = nil,
                similarArtist: [Artist]? = nil) {
        self.biography = biography
        self.musicBrainzId = musicBrainzId
        self.lastFmUrl = lastFmUrl
        self.smallImageUrl = smallImageUrl
        self.mediumImageUrl = mediumImageUrl
        self.largeImageUrl = largeImageUrl
        self.similarArtist = similarArtist
    }
}

public struct ScanStatus: Codable, Hashable, Sendable {
    public let scanning: Bool
    public let count: Int?
    public let folderCount: Int?
    public let lastScan: String?
    public init(scanning: Bool, count: Int? = nil, folderCount: Int? = nil, lastScan: String? = nil) {
        self.scanning = scanning
        self.count = count
        self.folderCount = folderCount
        self.lastScan = lastScan
    }
}

public struct SharesPayload: Codable, Sendable {
    public let share: [SubsonicShare]?
    public init(share: [SubsonicShare]? = nil) {
        self.share = share
    }
}

public struct SubsonicShare: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let url: String
    public let description: String?
    public let username: String?
    public let created: String?
    public let expires: String?
    public let lastVisited: String?
    public let visitCount: Int?
    public let entry: [SubsonicSong]?
    public init(id: String, url: String, description: String? = nil, username: String? = nil,
                created: String? = nil, expires: String? = nil, lastVisited: String? = nil,
                visitCount: Int? = nil, entry: [SubsonicSong]? = nil) {
        self.id = id
        self.url = url
        self.description = description
        self.username = username
        self.created = created
        self.expires = expires
        self.lastVisited = lastVisited
        self.visitCount = visitCount
        self.entry = entry
    }
}
