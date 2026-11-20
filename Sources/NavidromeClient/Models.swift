import Foundation

public struct SubsonicResponse: Decodable {
    public let subsonicResponse: SubsonicEnvelope

    private enum CodingKeys: String, CodingKey {
        case subsonicResponse = "subsonic-response"
    }
}

public struct SubsonicEnvelope: Decodable {
    public let status: String
    public let version: String?
    public let type: String?
    public let serverVersion: String?
    public let openSubsonic: Bool?
    public let error: SubsonicErrorPayload?

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
    public let artistInfo: ArtistInfoPayload?
    public let artistInfo2: ArtistInfoPayload?
    public let topSongs: SongListPayload?
    public let similarSongs: SongListPayload?
    public let similarSongs2: SongListPayload?
    public let scanStatus: ScanStatus?
    public let shares: SharesPayload?
    public let openSubsonicExtensions: [OpenSubsonicExtension]?

    public final class SubsonicErrorPayload: Decodable {
        public let code: Int
        public let message: String
        public init(code: Int, message: String) {
            self.code = code
            self.message = message
        }
    }
}

// MARK: - Entities

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

public struct ArtistIndex: Codable, Hashable {
    public let name: String
    public let artist: [Artist]?
    public init(name: String, artist: [Artist]? = nil) { self.name = name; self.artist = artist }
}

public struct Artist: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let albumCount: Int?
    public let artistImageUrl: String?
    public let coverArt: String?
    public let starred: String?
    public let averageRating: Double?
    public let userRating: Int?
    public init(id: String, name: String, albumCount: Int? = nil, artistImageUrl: String? = nil,
                coverArt: String? = nil, starred: String? = nil, averageRating: Double? = nil, userRating: Int? = nil) {
        self.id = id
        self.name = name
        self.albumCount = albumCount
        self.artistImageUrl = artistImageUrl
        self.coverArt = coverArt
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
    public let releaseTypes: [String]?
    public let discTitles: [DiscTitle]?
    public let explicitStatus: String?
    public let displayArtist: String?
    public let isCompilation: Bool?
    public let version: String?

    public var displayName: String { title ?? album ?? name ?? id }

    public var isExplicit: Bool {
        explicitStatus?.uppercased() == "EXPLICIT" || explicitStatus?.uppercased() == "E"
    }

    public var formattedReleaseType: String? {
        if let types = releaseTypes, let first = types.first(where: { !$0.isEmpty }) {
            return first
        }
        return recordType
    }

    public func discTitle(for discNumber: Int) -> String? {
        discTitles?.first(where: { $0.disc == discNumber })?.title
    }

    public init(id: String, parent: String? = nil, isDir: Bool? = nil, title: String? = nil, album: String? = nil,
                name: String? = nil, artist: String? = nil, artistId: String? = nil, coverArt: String? = nil,
                songCount: Int? = nil, duration: Int? = nil, playCount: Int? = nil, created: String? = nil,
                year: Int? = nil, genre: String? = nil, starId: String? = nil, starred: String? = nil,
                recordType: String? = nil, musicBrainzId: String? = nil, releaseTypes: [String]? = nil,
                discTitles: [DiscTitle]? = nil, explicitStatus: String? = nil, displayArtist: String? = nil,
                isCompilation: Bool? = nil, version: String? = nil) {
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
        self.releaseTypes = releaseTypes
        self.discTitles = discTitles
        self.explicitStatus = explicitStatus
        self.displayArtist = displayArtist
        self.isCompilation = isCompilation
        self.version = version
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
    public let albumArtistId: String?
    public let composer: String?
    public let artists: [Artist]?
    public let type: String?
    public let streamId: String?
    public let isVideo: Bool?
    public let bookmarkPosition: Int?
    public let sortName: String?
    public let musicBrainzId: String?
    public let bpm: Int?
    public let comment: String?
    public let replayGain: SubsonicReplayGain?
    public let displayArtist: String?
    public let albumArtists: [Artist]?
    public let displayAlbumArtist: String?
    public let contributors: [SubsonicContributor]?
    public let displayComposer: String?
    public let explicitStatus: String?

    public var displayTitle: String {
        if let title, !title.isEmpty { return title }
        return String(format: "Track %02d", track ?? 0)
    }

    public var displaySubtitle: String {
        [artist, album].compactMap { $0 }.joined(separator: " — ")
    }

    public var effectiveAlbumArtist: String {
        resolvedAlbumArtist
    }

    public var resolvedAlbumArtist: String {
        displayAlbumArtist ?? albumArtist ?? albumArtists?.first?.name ?? artist ?? "Unknown Artist"
    }

    public var resolvedAlbumArtistId: String? {
        albumArtistId ?? albumArtists?.first?.id ?? artistId
    }

    public var resolvedComposer: String? {
        if let displayComposer, !displayComposer.isEmpty { return displayComposer }
        if let composer, !composer.isEmpty { return composer }
        let composerContributors = contributors?.filter { $0.role.lowercased() == "composer" }
        if let first = composerContributors?.first?.artist.name { return first }
        return nil
    }

    public var isExplicit: Bool {
        explicitStatus?.uppercased() == "EXPLICIT" || explicitStatus?.uppercased() == "E"
    }

    public var isVariousArtists: Bool {
        guard let albumArtist else { return false }
        let lower = albumArtist.lowercased()
        return lower == "various artists" || lower == "various" || lower == "soundtrack" || lower == "va"
    }

    public init(id: String, parent: String? = nil, isDir: Bool? = nil, title: String? = nil, album: String? = nil,
                artist: String? = nil, track: Int? = nil, year: Int? = nil, genre: String? = nil,
                coverArt: String? = nil, size: Int? = nil, contentType: String? = nil, suffix: String? = nil,
                transcodedContentType: String? = nil, transcodedSuffix: String? = nil, duration: Int? = nil,
                bitRate: Int? = nil, path: String? = nil, playCount: Int? = nil, discNumber: Int? = nil,
                created: String? = nil, starred: String? = nil, userRating: Int? = nil, averageRating: Double? = nil,
                albumId: String? = nil, artistId: String? = nil, albumArtist: String? = nil,
                albumArtistId: String? = nil, composer: String? = nil, artists: [Artist]? = nil,
                type: String? = nil, streamId: String? = nil, isVideo: Bool? = nil,
                bookmarkPosition: Int? = nil, sortName: String? = nil, musicBrainzId: String? = nil,
                bpm: Int? = nil, comment: String? = nil, replayGain: SubsonicReplayGain? = nil,
                displayArtist: String? = nil, albumArtists: [Artist]? = nil, displayAlbumArtist: String? = nil,
                contributors: [SubsonicContributor]? = nil, displayComposer: String? = nil,
                explicitStatus: String? = nil) {
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
        self.albumArtistId = albumArtistId
        self.composer = composer
        self.artists = artists
        self.type = type
        self.streamId = streamId
        self.isVideo = isVideo
        self.bookmarkPosition = bookmarkPosition
        self.sortName = sortName
        self.musicBrainzId = musicBrainzId
        self.bpm = bpm
        self.comment = comment
        self.replayGain = replayGain
        self.displayArtist = displayArtist
        self.albumArtists = albumArtists
        self.displayAlbumArtist = displayAlbumArtist
        self.contributors = contributors
        self.displayComposer = displayComposer
        self.explicitStatus = explicitStatus
    }
}

public struct SubsonicReplayGain: Codable, Hashable, Sendable {
    public let trackGain: Double?
    public let albumGain: Double?
    public let trackPeak: Double?
    public let albumPeak: Double?
    public let baseGain: Double?
    public let fallbackGain: Double?

    public init(
        trackGain: Double? = nil,
        albumGain: Double? = nil,
        trackPeak: Double? = nil,
        albumPeak: Double? = nil,
        baseGain: Double? = nil,
        fallbackGain: Double? = nil
    ) {
        self.trackGain = trackGain
        self.albumGain = albumGain
        self.trackPeak = trackPeak
        self.albumPeak = albumPeak
        self.baseGain = baseGain
        self.fallbackGain = fallbackGain
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
    public let releaseTypes: [String]?
    public let discTitles: [DiscTitle]?
    public let explicitStatus: String?
    public let displayArtist: String?
    public let isCompilation: Bool?
    public let version: String?

    public var displayName: String { name?.isEmpty == false ? name! : id }

    public var isExplicit: Bool {
        explicitStatus?.uppercased() == "EXPLICIT" || explicitStatus?.uppercased() == "E"
    }

    public var formattedReleaseType: String? {
        if let types = releaseTypes, let first = types.first(where: { !$0.isEmpty }) {
            return first
        }
        return recordType
    }

    public func discTitle(for discNumber: Int) -> String? {
        discTitles?.first(where: { $0.disc == discNumber })?.title
    }

    public init(id: String, name: String? = nil, artist: String? = nil, artistId: String? = nil,
                coverArt: String? = nil, songCount: Int? = nil, duration: Int? = nil, playCount: Int? = nil,
                created: String? = nil, year: Int? = nil, genre: String? = nil, recordType: String? = nil,
                musicBrainzId: String? = nil, starred: String? = nil, starId: String? = nil,
                song: [SubsonicSong]? = nil, releaseTypes: [String]? = nil, discTitles: [DiscTitle]? = nil,
                explicitStatus: String? = nil, displayArtist: String? = nil, isCompilation: Bool? = nil,
                version: String? = nil) {
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
        self.releaseTypes = releaseTypes
        self.discTitles = discTitles
        self.explicitStatus = explicitStatus
        self.displayArtist = displayArtist
        self.isCompilation = isCompilation
        self.version = version
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