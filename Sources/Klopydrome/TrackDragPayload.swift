import CoreTransferable
import Foundation
import UniformTypeIdentifiers

extension UTType {
    public static var trackDragPayload: UTType {
        UTType(exportedAs: "com.klopydrome.track-drag", conformingTo: .data)
    }
}

public struct TrackDragPayload: Codable, Hashable, Sendable, Transferable {
    public enum Kind: Codable, Hashable, Sendable {
        case songs([String])
        case album(String)
        case queueItem(index: Int, songID: String)
        case playlistTrack(playlistID: String, index: Int, songID: String)
    }

    public let kind: Kind

    public init(kind: Kind) {
        self.kind = kind
    }

    public static func songs(_ ids: [String]) -> TrackDragPayload {
        TrackDragPayload(kind: .songs(ids))
    }

    public static func song(_ id: String) -> TrackDragPayload {
        TrackDragPayload(kind: .songs([id]))
    }

    public static func album(_ id: String) -> TrackDragPayload {
        TrackDragPayload(kind: .album(id))
    }

    public static func queueItem(index: Int, songID: String) -> TrackDragPayload {
        TrackDragPayload(kind: .queueItem(index: index, songID: songID))
    }

    public static func playlistTrack(playlistID: String, index: Int, songID: String) -> TrackDragPayload {
        TrackDragPayload(kind: .playlistTrack(playlistID: playlistID, index: index, songID: songID))
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .trackDragPayload)
    }
}
