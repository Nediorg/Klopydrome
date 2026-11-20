import Foundation

public struct DiscTitle: Codable, Hashable, Sendable {
    public let disc: Int
    public let title: String
    public let coverArt: String?

    public init(disc: Int, title: String, coverArt: String? = nil) {
        self.disc = disc
        self.title = title
        self.coverArt = coverArt
    }
}

public struct SubsonicContributor: Codable, Hashable, Sendable {
    public let role: String
    public let subRole: String?
    public let artist: Artist

    public init(role: String, subRole: String? = nil, artist: Artist) {
        self.role = role
        self.subRole = subRole
        self.artist = artist
    }
}

public struct OpenSubsonicExtension: Codable, Equatable, Sendable {
    public let name: String
    public let versions: [Int]

    public init(name: String, versions: [Int] = []) {
        self.name = name
        self.versions = versions
    }
}
