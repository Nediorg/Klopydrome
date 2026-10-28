import Foundation

public struct LyricsResult: Codable {
    public let artist: String?
    public let title: String?
    public let value: String?
    public init(artist: String? = nil, title: String? = nil, value: String? = nil) {
        self.artist = artist
        self.title = title
        self.value = value
    }
}

public struct SyncedLine: Codable, Hashable {
    public let start: Double?
    public let value: String?
    public init(start: Double? = nil, value: String? = nil) { self.start = start; self.value = value }
}

public struct LyricsCue: Codable, Hashable {
    public let start: Double?
    public let end: Double?
    public let byteStart: Int?
    public let byteEnd: Int?
    public let value: String?
    public init(start: Double? = nil, end: Double? = nil, byteStart: Int? = nil,
                byteEnd: Int? = nil, value: String? = nil) {
        self.start = start
        self.end = end
        self.byteStart = byteStart
        self.byteEnd = byteEnd
        self.value = value
    }
}

public struct LyricsCueLine: Codable, Hashable {
    public let index: Int?
    public let start: Double?
    public let end: Double?
    public let value: String?
    public let agentId: String?
    public let cue: [LyricsCue]?
    public init(index: Int? = nil, start: Double? = nil, end: Double? = nil,
                value: String? = nil, agentId: String? = nil, cue: [LyricsCue]? = nil) {
        self.index = index
        self.start = start
        self.end = end
        self.value = value
        self.agentId = agentId
        self.cue = cue
    }
}

public struct LyricsEntry: Codable {
    public let artist: String?
    public let title: String?
    public let synced: Bool?
    public let lang: String?
    public let displayArtist: String?
    public let displayTitle: String?
    public let line: [SyncedLine]?
    public let cueLine: [LyricsCueLine]?
    public let offset: Double?
    public init(artist: String? = nil, title: String? = nil, synced: Bool? = nil,
                lang: String? = nil, displayArtist: String? = nil, displayTitle: String? = nil,
                line: [SyncedLine]? = nil, cueLine: [LyricsCueLine]? = nil, offset: Double? = nil) {
        self.artist = artist
        self.title = title
        self.synced = synced
        self.lang = lang
        self.displayArtist = displayArtist
        self.displayTitle = displayTitle
        self.line = line
        self.cueLine = cueLine
        self.offset = offset
    }
}

public struct LyricsListResult: Codable {
    public let structuredLyrics: [LyricsEntry]?
    public let lyrics: [LyricsEntry]?
    public init(structuredLyrics: [LyricsEntry]? = nil, lyrics: [LyricsEntry]? = nil) {
        self.structuredLyrics = structuredLyrics
        self.lyrics = lyrics
    }
}
