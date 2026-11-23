import Foundation
import NavidromeClient

struct AudioTagMetadata: Sendable {
    let title: String?
    let artist: String?
    let albumArtist: String?
    let album: String?
    let genre: String?
    let year: Int?
    let trackNumber: Int?
    let discNumber: Int?
    let bpm: Int?
    let coverArtData: Data?
    let coverArtMimeType: String?

    init(song: SubsonicSong, coverArtData: Data? = nil) {
        self.title = song.displayTitle
        self.artist = song.artist
        self.albumArtist = song.albumArtist ?? song.artist
        self.album = song.album
        self.genre = song.genre
        self.year = song.year
        self.trackNumber = song.track
        self.discNumber = song.discNumber
        self.bpm = song.bpm
        self.coverArtData = coverArtData
        self.coverArtMimeType = Self.detectImageMimeType(coverArtData)
    }

    init(
        title: String? = nil,
        artist: String? = nil,
        albumArtist: String? = nil,
        album: String? = nil,
        genre: String? = nil,
        year: Int? = nil,
        trackNumber: Int? = nil,
        discNumber: Int? = nil,
        bpm: Int? = nil,
        coverArtData: Data? = nil
    ) {
        self.title = title
        self.artist = artist
        self.albumArtist = albumArtist
        self.album = album
        self.genre = genre
        self.year = year
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.bpm = bpm
        self.coverArtData = coverArtData
        self.coverArtMimeType = Self.detectImageMimeType(coverArtData)
    }

    private static func detectImageMimeType(_ data: Data?) -> String? {
        guard let data, data.count >= 4 else { return nil }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return "image/png"
        }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) {
            return "image/jpeg"
        }
        return "image/jpeg"
    }
}
