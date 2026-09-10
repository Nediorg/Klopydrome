import Foundation

// MARK: - Playlists

public struct PlaylistSummary: Codable, Hashable, Identifiable {
    public let id: String
    public let name: String?
    public let comment: String?
    public let owner: String?
    public let coverArt: String?
    public let songCount: Int?
    public let duration: Int?
    public let created: String?
    public let changed: String?
    public let isPublic: Bool?
    /// OpenSubsonic: `true` when the current user cannot edit the playlist's
    /// tracks. Navidrome sets it for smart playlists (always) and for playlists
    /// owned by another user. Do NOT use this to detect a smart playlist.
    public let isReadonly: Bool?
    /// OpenSubsonic: present only on server-side smart playlists (rules
    /// evaluated by the server). This is the reliable smart-playlist marker —
    /// unlike `isReadonly`, which also marks shared playlists.
    public let validUntil: String?

    public var displayName: String { name?.isEmpty == false ? name! : id }

    /// True for server-side smart playlists (rules stored/evaluated on the
    /// server). Navidrome emits `validUntil` only for those, so its presence is
    /// the discriminator — `isReadonly` alone would also match shared playlists.
    public var isSmart: Bool { validUntil != nil }

    public init(id: String, name: String? = nil, comment: String? = nil, owner: String? = nil,
                coverArt: String? = nil, songCount: Int? = nil, duration: Int? = nil, created: String? = nil,
                changed: String? = nil, isPublic: Bool? = nil, isReadonly: Bool? = nil, validUntil: String? = nil) {
        self.id = id
        self.name = name
        self.comment = comment
        self.owner = owner
        self.coverArt = coverArt
        self.songCount = songCount
        self.duration = duration
        self.created = created
        self.changed = changed
        self.isPublic = isPublic
        self.isReadonly = isReadonly
        self.validUntil = validUntil
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, comment, owner, coverArt, songCount, duration, created, changed
        case isPublic = "public"
        case isReadonly = "readonly"
        case validUntil
    }
}

public struct PlaylistDetail: Codable, Hashable, Identifiable {
    public let id: String
    public let name: String?
    public let comment: String?
    public let owner: String?
    public let coverArt: String?
    public let songCount: Int?
    public let duration: Int?
    public let created: String?
    public let changed: String?
    public let isPublic: Bool?
    public let isReadonly: Bool?
    public let validUntil: String?
    public let entry: [SubsonicSong]?

    public var displayName: String { name?.isEmpty == false ? name! : id }

    /// True for server-side smart playlists (see `PlaylistSummary.isSmart`).
    public var isSmart: Bool { validUntil != nil }

    public init(id: String, name: String? = nil, comment: String? = nil, owner: String? = nil,
                coverArt: String? = nil, songCount: Int? = nil, duration: Int? = nil, created: String? = nil,
                changed: String? = nil, isPublic: Bool? = nil, isReadonly: Bool? = nil,
                validUntil: String? = nil, entry: [SubsonicSong]? = nil) {
        self.id = id
        self.name = name
        self.comment = comment
        self.owner = owner
        self.coverArt = coverArt
        self.songCount = songCount
        self.duration = duration
        self.created = created
        self.changed = changed
        self.isPublic = isPublic
        self.isReadonly = isReadonly
        self.validUntil = validUntil
        self.entry = entry
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, comment, owner, coverArt, songCount, duration, created, changed, entry
        case isPublic = "public"
        case isReadonly = "readonly"
        case validUntil
    }
}

/// A slice of a playlist load: either the header metadata or a chunk of songs.
/// `getPlaylist` returns the entire playlist in one payload, but for huge
/// playlists decoding the whole `entry` list in a single shot blocks the first
/// paint. The streaming client decodes header first, then yields songs in
/// bounded chunks so the UI can render as soon as the first chunk arrives.
public enum PlaylistChunk {
    case header(PlaylistDetail)
    case songs([SubsonicSong])
}
