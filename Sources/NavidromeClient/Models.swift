import Foundation

/// Top-level envelope every Subsonic JSON response is wrapped in.
public struct SubsonicResponse: Decodable {
    public let subsonicResponse: SubsonicEnvelope

    private enum CodingKeys: String, CodingKey {
        case subsonicResponse = "subsonic-response"
    }
}

/// The inner `subsonic-response` object. All payload keys are optional so a single
/// decoder can be shared across endpoints.
public struct SubsonicEnvelope: Decodable {
    public let status: String
    public let version: String?
    public let type: String?
    public let serverVersion: String?
    public let openSubsonic: Bool?
    public let error: SubsonicErrorPayload?

    // Payloads
    public let albumList2: AlbumList?
    public let album: AlbumDetail?
    public let song: SubsonicSong?
    public let artist: ArtistDetail?
    public let artists: ArtistsPayload?
    public let searchResult3: SearchResultPayload?
    public let playlists: PlaylistsPayload?
    public let playlist: PlaylistDetail?
    public let lyrics: LyricsResult?
    public let lyricsList: LyricsListResult?
    public let starred2: SearchResultPayload?
    public let playQueue: PlayQueuePayload?
    public let songsByGenre: SongListPayload?
    public let genres: GenresPayload?
    public let albumInfo: AlbumInfoPayload?

    public final class SubsonicErrorPayload: Decodable {
        public let code: Int
        public let message: String
        public init(code: Int, message: String) {
            self.code = code
            self.message = message
        }
    }
}

// MARK: - Payloads

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

public struct Genre: Codable, Hashable, Identifiable {
    public let value: String?
    public let songCount: Int?
    public let albumCount: Int?
    public var id: String { value ?? "" }
    public init(value: String? = nil, songCount: Int? = nil, albumCount: Int? = nil) {
        self.value = value
        self.songCount = songCount
        self.albumCount = albumCount
    }
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

// MARK: - Entities

public struct ArtistIndex: Codable, Hashable {
    public let name: String
    public let artist: [Artist]?
    public init(name: String, artist: [Artist]? = nil) { self.name = name; self.artist = artist }
}

public struct Artist: Codable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let albumCount: Int?
    public let artistImageUrl: String?
    public let starred: String?
    public let averageRating: Double?
    public let userRating: Int?
    public init(id: String, name: String, albumCount: Int? = nil, artistImageUrl: String? = nil,
                starred: String? = nil, averageRating: Double? = nil, userRating: Int? = nil) {
        self.id = id
        self.name = name
        self.albumCount = albumCount
        self.artistImageUrl = artistImageUrl
        self.starred = starred
        self.averageRating = averageRating
        self.userRating = userRating
    }
}

public struct SubsonicAlbum: Codable, Hashable, Identifiable {
    public let id: String
    public let parent: String?
    public let isDir: Bool?
    public let title: String?
    public let album: String?
    public let name: String?
    public let artist: String?
    public let artistId: String?
    public let coverArt: String?
    public let songCount: Int?
    public let duration: Int?
    public let playCount: Int?
    public let created: String?
    public let year: Int?
    public let genre: String?
    public let starId: String?
    public let starred: String?
    public let recordType: String?
    public let musicBrainzId: String?

    public var displayName: String { title ?? album ?? name ?? id }

    public init(id: String, parent: String? = nil, isDir: Bool? = nil, title: String? = nil, album: String? = nil,
                name: String? = nil, artist: String? = nil, artistId: String? = nil, coverArt: String? = nil,
                songCount: Int? = nil, duration: Int? = nil, playCount: Int? = nil, created: String? = nil,
                year: Int? = nil, genre: String? = nil, starId: String? = nil, starred: String? = nil,
                recordType: String? = nil, musicBrainzId: String? = nil) {
        self.id = id
        self.parent = parent
        self.isDir = isDir
        self.title = title
        self.album = album
        self.name = name
        self.artist = artist
        self.artistId = artistId
        self.coverArt = coverArt
        self.songCount = songCount
        self.duration = duration
        self.playCount = playCount
        self.created = created
        self.year = year
        self.genre = genre
        self.starId = starId
        self.starred = starred
        self.recordType = recordType
        self.musicBrainzId = musicBrainzId
    }
}

public struct SubsonicSong: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let parent: String?
    public let isDir: Bool?
    public let title: String?
    public let album: String?
    public let artist: String?
    public let track: Int?
    public let year: Int?
    public let genre: String?
    public let coverArt: String?
    public let size: Int?
    public let contentType: String?
    public let suffix: String?
    public let transcodedContentType: String?
    public let transcodedSuffix: String?
    public let duration: Int?
    public let bitRate: Int?
    public let path: String?
    public let playCount: Int?
    public let discNumber: Int?
    public let created: String?
    public let starred: String?
    public let userRating: Int?
    public let averageRating: Double?
    public let albumId: String?
    public let artistId: String?
    public let albumArtist: String?
    public let type: String?
    public let streamId: String?
    public let isVideo: Bool?
    public let bookmarkPosition: Int?
    public let sortName: String?
    public let musicBrainzId: String?

    public var displayTitle: String {
        if let title, !title.isEmpty { return title }
        return String(format: "Track %02d", track ?? 0)
    }

    /// Canonical "Artist — Album" subtitle template shared by every now-playing
    /// surface (LCD, mini player, queue, song rows).
    public var displaySubtitle: String {
        [artist, album].compactMap { $0 }.joined(separator: " — ")
    }

    public init(id: String, parent: String? = nil, isDir: Bool? = nil, title: String? = nil, album: String? = nil,
                artist: String? = nil, track: Int? = nil, year: Int? = nil, genre: String? = nil,
                coverArt: String? = nil, size: Int? = nil, contentType: String? = nil, suffix: String? = nil,
                transcodedContentType: String? = nil, transcodedSuffix: String? = nil, duration: Int? = nil,
                bitRate: Int? = nil, path: String? = nil, playCount: Int? = nil, discNumber: Int? = nil,
                created: String? = nil, starred: String? = nil, userRating: Int? = nil, averageRating: Double? = nil,
                albumId: String? = nil, artistId: String? = nil, albumArtist: String? = nil, type: String? = nil,
                streamId: String? = nil, isVideo: Bool? = nil, bookmarkPosition: Int? = nil,
                sortName: String? = nil, musicBrainzId: String? = nil) {
        self.id = id
        self.parent = parent
        self.isDir = isDir
        self.title = title
        self.album = album
        self.artist = artist
        self.track = track
        self.year = year
        self.genre = genre
        self.coverArt = coverArt
        self.size = size
        self.contentType = contentType
        self.suffix = suffix
        self.transcodedContentType = transcodedContentType
        self.transcodedSuffix = transcodedSuffix
        self.duration = duration
        self.bitRate = bitRate
        self.path = path
        self.playCount = playCount
        self.discNumber = discNumber
        self.created = created
        self.starred = starred
        self.userRating = userRating
        self.averageRating = averageRating
        self.albumId = albumId
        self.artistId = artistId
        self.albumArtist = albumArtist
        self.type = type
        self.streamId = streamId
        self.isVideo = isVideo
        self.bookmarkPosition = bookmarkPosition
        self.sortName = sortName
        self.musicBrainzId = musicBrainzId
    }
}

public struct AlbumDetail: Codable, Hashable, Identifiable {
    public let id: String
    public let name: String?
    public let artist: String?
    public let artistId: String?
    public let coverArt: String?
    public let songCount: Int?
    public let duration: Int?
    public let playCount: Int?
    public let created: String?
    public let year: Int?
    public let genre: String?
    public let recordType: String?
    public let musicBrainzId: String?
    public let starred: String?
    public let starId: String?
    public let song: [SubsonicSong]?

    public var displayName: String { name?.isEmpty == false ? name! : id }

    public init(id: String, name: String? = nil, artist: String? = nil, artistId: String? = nil,
                coverArt: String? = nil, songCount: Int? = nil, duration: Int? = nil, playCount: Int? = nil,
                created: String? = nil, year: Int? = nil, genre: String? = nil, recordType: String? = nil,
                musicBrainzId: String? = nil, starred: String? = nil, starId: String? = nil,
                song: [SubsonicSong]? = nil) {
        self.id = id
        self.name = name
        self.artist = artist
        self.artistId = artistId
        self.coverArt = coverArt
        self.songCount = songCount
        self.duration = duration
        self.playCount = playCount
        self.created = created
        self.year = year
        self.genre = genre
        self.recordType = recordType
        self.musicBrainzId = musicBrainzId
        self.starred = starred
        self.starId = starId
        self.song = song
    }
}

public struct ArtistDetail: Codable, Hashable, Identifiable {
    public let id: String
    public let name: String?
    public let coverArt: String?
    public let albumCount: Int?
    public let artistImageUrl: String?
    public let starred: String?
    public let album: [SubsonicAlbum]?
    /// OpenSubsonic role tags (`artist`, `albumartist`, `composer`, …). Lets the
    /// UI label an artist by what they actually do instead of assuming "artist".
    public let roles: [String]?
    public init(id: String, name: String? = nil, coverArt: String? = nil, albumCount: Int? = nil,
                artistImageUrl: String? = nil, starred: String? = nil, album: [SubsonicAlbum]? = nil,
                roles: [String]? = nil) {
        self.id = id
        self.name = name
        self.coverArt = coverArt
        self.albumCount = albumCount
        self.artistImageUrl = artistImageUrl
        self.starred = starred
        self.album = album
        self.roles = roles
    }
}