import Foundation

// MARK: - Lyrics

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

/// A word-level cue inside a `LyricsCueLine`. Times are milliseconds and match
/// the `line.start` clock (server-side `LyricCue`). `end` is only present when
/// the server could resolve it (missing when every cue of a line is start-only).
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

/// One WordSync (karaoke) block for a line. The server emits it only when the
/// lyrics are requested with `enhanced=true` and attaches `index` — the index
/// of the `SyncedLine` the cues belong to. Multiple agents may share an index;
/// the primary vocal's block is emitted first (main role).
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
    /// Word-level karaoke blocks, present only for `enhanced` requests. Top
    /// level on the entry; each block's `index` points at the line it belongs
    /// to (see `LyricsCueLine.index`).
    public let cueLine: [LyricsCueLine]?
    /// LRC `[offset:±N]` tag in milliseconds, passed through as-is by the
    /// server (Navidrome does NOT bake it into `line.start`). Applied by the
    /// client as `probe = audio + offset`, so the highlight lands where the
    /// lyrics author intended. Positive = highlight earlier.
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
    /// Navidrome/OpenSubsonic return synced lyrics under `structuredLyrics`, not `lyrics`.
    public let structuredLyrics: [LyricsEntry]?
    public let lyrics: [LyricsEntry]?
    public init(structuredLyrics: [LyricsEntry]? = nil, lyrics: [LyricsEntry]? = nil) {
        self.structuredLyrics = structuredLyrics
        self.lyrics = lyrics
    }
}
