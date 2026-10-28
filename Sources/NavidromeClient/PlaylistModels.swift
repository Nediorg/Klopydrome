import Foundation

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
    public let isReadonly: Bool?
    public let validUntil: String?

    public var displayName: String { name?.isEmpty == false ? name! : id }

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

public enum PlaylistChunk {
    case header(PlaylistDetail)
    case songs([SubsonicSong])
}
