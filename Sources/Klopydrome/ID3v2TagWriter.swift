import Foundation
import NavidromeClient

enum ID3v2TagWriter {
    static func write(_ metadata: AudioTagMetadata, toMP3At url: URL) throws {
        let tagData = buildID3v23Tag(from: metadata)
        let existingOffset = try existingID3v2Size(at: url)

        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).mp3")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        let writer = try FileHandle(forWritingTo: tempURL)
        defer { try? writer.close() }

        try writer.write(contentsOf: tagData)

        let reader = try FileHandle(forReadingFrom: url)
        defer { try? reader.close() }
        try reader.seek(toOffset: UInt64(existingOffset))

        while true {
            let chunk = try reader.read(upToCount: 256 * 1024) ?? Data()
            if chunk.isEmpty { break }
            try writer.write(contentsOf: chunk)
        }
        try writer.synchronize()
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
    }

    private static func existingID3v2Size(at url: URL) throws -> Int {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: 10) ?? Data()
        guard header.count == 10,
              header[0] == 0x49, header[1] == 0x44, header[2] == 0x33 else {
            return 0
        }
        let bodySize = (Int(header[6] & 0x7F) << 21)
            | (Int(header[7] & 0x7F) << 14)
            | (Int(header[8] & 0x7F) << 7)
            | Int(header[9] & 0x7F)
        let hasFooter = (header[5] & 0x10) != 0
        return 10 + bodySize + (hasFooter ? 10 : 0)
    }

    private static func buildID3v23Tag(from m: AudioTagMetadata) -> Data {
        var frames = Data()
        if let v = m.title, !v.isEmpty { frames.append(textFrame("TIT2", value: v)) }
        if let v = m.artist, !v.isEmpty { frames.append(textFrame("TPE1", value: v)) }
        if let v = m.albumArtist, !v.isEmpty { frames.append(textFrame("TPE2", value: v)) }
        if let v = m.album, !v.isEmpty { frames.append(textFrame("TALB", value: v)) }
        if let v = m.genre, !v.isEmpty { frames.append(textFrame("TCON", value: v)) }
        if let t = m.trackNumber, t > 0 { frames.append(textFrame("TRCK", value: "\(t)")) }
        if let d = m.discNumber, d > 0 { frames.append(textFrame("TPOS", value: "\(d)")) }
        if let y = m.year, y > 0 { frames.append(textFrame("TYER", value: "\(y)")) }
        if let b = m.bpm, b > 0 { frames.append(textFrame("TBPM", value: "\(b)")) }
        if let img = m.coverArtData, !img.isEmpty {
            frames.append(apicFrame(imageData: img, mimeType: m.coverArtMimeType ?? "image/jpeg"))
        }

        var tag = Data([0x49, 0x44, 0x33, 0x03, 0x00, 0x00])
        tag.append(synchsafeUInt32(UInt32(frames.count)))
        tag.append(frames)
        return tag
    }

    private static func textFrame(_ id: String, value: String) -> Data {
        var payload = Data([0x01, 0xFF, 0xFE])
        if let utf16 = value.data(using: .utf16LittleEndian) {
            payload.append(utf16)
        }
        return frame(id, payload: payload)
    }

    private static func apicFrame(imageData: Data, mimeType: String) -> Data {
        var payload = Data([0x00])
        payload.append(Data(mimeType.utf8))
        payload.append(0x00)
        payload.append(0x03)
        payload.append(0x00)
        payload.append(imageData)
        return frame("APIC", payload: payload)
    }

    private static func frame(_ id: String, payload: Data) -> Data {
        var out = Data(id.utf8.prefix(4))
        var sizeBE = UInt32(payload.count).bigEndian
        out.append(Data(bytes: &sizeBE, count: 4))
        out.append(contentsOf: [0x00, 0x00])
        out.append(payload)
        return out
    }

    private static func synchsafeUInt32(_ value: UInt32) -> Data {
        Data([
            UInt8((value >> 21) & 0x7F),
            UInt8((value >> 14) & 0x7F),
            UInt8((value >> 7) & 0x7F),
            UInt8(value & 0x7F)
        ])
    }
}
