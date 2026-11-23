import CoreTransferable
import Foundation
import UniformTypeIdentifiers

extension UTType {
    public static var trackDragPayload: UTType {
        UTType(exportedAs: "com.klopydrome.track-drag", conformingTo: .data)
    }
}

public struct TrackDragPayload: Codable, Hashable, Sendable, Transferable {
    public struct ExportInfo: Codable, Hashable, Sendable {
        public let suggestedFilename: String
        public let canExport: Bool
        public let suffix: String?
        public let duration: Int?

        public init(
            suggestedFilename: String,
            canExport: Bool,
            suffix: String? = nil,
            duration: Int? = nil
        ) {
            self.suggestedFilename = suggestedFilename
            self.canExport = canExport
            self.suffix = suffix
            self.duration = duration
        }
    }

    public enum Kind: Codable, Hashable, Sendable {
        case songs([String])
        case album(String)
        case queueItem(index: Int, songID: String)
        case playlistTrack(playlistID: String, index: Int, songID: String)
    }

    public let kind: Kind
    public let exportInfo: ExportInfo?

    public init(kind: Kind, exportInfo: ExportInfo? = nil) {
        self.kind = kind
        self.exportInfo = exportInfo
    }

    public var singleSongID: String? {
        switch kind {
        case .songs(let ids) where ids.count == 1:
            return ids[0]
        case .queueItem(_, let songID), .playlistTrack(_, _, let songID):
            return songID
        default:
            return nil
        }
    }

    public var canExportSingleFile: Bool {
        exportInfo?.canExport == true && singleSongID != nil
    }

    public static func songs(_ ids: [String], exportInfo: ExportInfo? = nil) -> TrackDragPayload {
        TrackDragPayload(kind: .songs(ids), exportInfo: ids.count == 1 ? exportInfo : nil)
    }

    public static func song(_ id: String, exportInfo: ExportInfo? = nil) -> TrackDragPayload {
        TrackDragPayload(kind: .songs([id]), exportInfo: exportInfo)
    }

    public static func album(_ id: String) -> TrackDragPayload {
        TrackDragPayload(kind: .album(id))
    }

    public static func queueItem(
        index: Int,
        songID: String,
        exportInfo: ExportInfo? = nil
    ) -> TrackDragPayload {
        TrackDragPayload(kind: .queueItem(index: index, songID: songID), exportInfo: exportInfo)
    }

    public static func playlistTrack(
        playlistID: String,
        index: Int,
        songID: String,
        exportInfo: ExportInfo? = nil
    ) -> TrackDragPayload {
        TrackDragPayload(
            kind: .playlistTrack(playlistID: playlistID, index: index, songID: songID),
            exportInfo: exportInfo
        )
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .trackDragPayload)
    }
}
