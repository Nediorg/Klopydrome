import Foundation
import NavidromeClient

enum FLACTagWriter {
    static func write(_ metadata: AudioTagMetadata, toFLACAt url: URL) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        guard let magic = try handle.read(upToCount: 4),
              magic == Data([0x66, 0x4C, 0x61, 0x43]) else {
            return
        }

        var audioStartOffset: UInt64 = 4
        var streamInfoBlock: Data?

        while true {
            guard let header = try handle.read(upToCount: 4), header.count == 4 else { break }
            let isLast = (header[0] & 0x80) != 0
            let type = header[0] & 0x7F
            let length = (Int(header[1]) << 16) | (Int(header[2]) << 8) | Int(header[3])
            guard let blockData = try handle.read(upToCount: length), blockData.count == length else { break }

            if type == 0 && streamInfoBlock == nil {
                streamInfoBlock = blockData
            }
            audioStartOffset += UInt64(4 + length)
            if isLast { break }
        }

        guard let streamInfo = streamInfoBlock else { return }
        try writeNewFLAC(
            metadata: metadata,
            streamInfo: streamInfo,
            audioStartOffset: audioStartOffset,
            sourceURL: url
        )
    }

    private static func writeNewFLAC(
        metadata: AudioTagMetadata,
        streamInfo: Data,
        audioStartOffset: UInt64,
        sourceURL: URL
    ) throws {
        let tempURL = sourceURL.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).flac")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        let writer = try FileHandle(forWritingTo: tempURL)
        defer { try? writer.close() }

        try writer.write(contentsOf: Data([0x66, 0x4C, 0x61, 0x43]))

        let vorbisComment = buildVorbisComment(from: metadata)
        let pictureBlock = metadata.coverArtData.flatMap {
            buildPictureBlock(imageData: $0, mimeType: metadata.coverArtMimeType ?? "image/jpeg")
        }

        let hasPicture = pictureBlock != nil
        try writeBlock(writer: writer, type: 0, isLast: false, data: streamInfo)
        try writeBlock(writer: writer, type: 4, isLast: !hasPicture, data: vorbisComment)
        if let pictureBlock {
            try writeBlock(writer: writer, type: 6, isLast: true, data: pictureBlock)
        }

        let reader = try FileHandle(forReadingFrom: sourceURL)
        defer { try? reader.close() }
        try reader.seek(toOffset: audioStartOffset)
        while true {
            let chunk = try reader.read(upToCount: 256 * 1024) ?? Data()
            if chunk.isEmpty { break }
            try writer.write(contentsOf: chunk)
        }
        try writer.synchronize()
        _ = try FileManager.default.replaceItemAt(sourceURL, withItemAt: tempURL)
    }

    private static func writeBlock(writer: FileHandle, type: UInt8, isLast: Bool, data: Data) throws {
        var header = [UInt8](repeating: 0, count: 4)
        header[0] = (isLast ? 0x80 : 0x00) | (type & 0x7F)
        let len = data.count
        header[1] = UInt8((len >> 16) & 0xFF)
        header[2] = UInt8((len >> 8) & 0xFF)
        header[3] = UInt8(len & 0xFF)
        try writer.write(contentsOf: Data(header))
        try writer.write(contentsOf: data)
    }

    private static func buildVorbisComment(from m: AudioTagMetadata) -> Data {
        var entries: [String] = []
        if let v = m.title, !v.isEmpty { entries.append("TITLE=\(v)") }
        if let v = m.artist, !v.isEmpty { entries.append("ARTIST=\(v)") }
        if let v = m.albumArtist, !v.isEmpty { entries.append("ALBUMARTIST=\(v)") }
        if let v = m.album, !v.isEmpty { entries.append("ALBUM=\(v)") }
        if let v = m.genre, !v.isEmpty { entries.append("GENRE=\(v)") }
        if let t = m.trackNumber, t > 0 { entries.append("TRACKNUMBER=\(t)") }
        if let d = m.discNumber, d > 0 { entries.append("DISCNUMBER=\(d)") }
        if let y = m.year, y > 0 { entries.append("DATE=\(y)") }

        var out = Data()
        let vendor = "Klopydrome"
        var vendorLen = UInt32(vendor.utf8.count).littleEndian
        out.append(Data(bytes: &vendorLen, count: 4))
        out.append(Data(vendor.utf8))

        var countLE = UInt32(entries.count).littleEndian
        out.append(Data(bytes: &countLE, count: 4))
        for entry in entries {
            let entryBytes = Data(entry.utf8)
            var lenLE = UInt32(entryBytes.count).littleEndian
            out.append(Data(bytes: &lenLE, count: 4))
            out.append(entryBytes)
        }
        return out
    }

    private static func buildPictureBlock(imageData: Data, mimeType: String) -> Data {
        var out = Data()
        var typeBE = UInt32(3).bigEndian
        out.append(Data(bytes: &typeBE, count: 4))

        let mimeBytes = Data(mimeType.utf8)
        var mimeLenBE = UInt32(mimeBytes.count).bigEndian
        out.append(Data(bytes: &mimeLenBE, count: 4))
        out.append(mimeBytes)

        var descLenBE = UInt32(0).bigEndian
        out.append(Data(bytes: &descLenBE, count: 4))

        let zeros = [UInt8](repeating: 0, count: 16)
        out.append(contentsOf: zeros)

        var imgLenBE = UInt32(imageData.count).bigEndian
        out.append(Data(bytes: &imgLenBE, count: 4))
        out.append(imageData)
        return out
    }
}
