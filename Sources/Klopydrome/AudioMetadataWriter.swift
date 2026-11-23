import Foundation
import NavidromeClient

enum AudioMetadataWriter {
    static func inject(_ metadata: AudioTagMetadata, into fileURL: URL) async throws {
        let header = readHeaderBytes(at: fileURL, count: 12)
        let ext = fileURL.pathExtension.lowercased()

        if isMP3(header: header, ext: ext) {
            try ID3v2TagWriter.write(metadata, toMP3At: fileURL)
        } else if isM4A(header: header, ext: ext) {
            try await M4AMetadataWriter.write(metadata, toM4AAt: fileURL)
        } else if isFLAC(header: header, ext: ext) {
            try FLACTagWriter.write(metadata, toFLACAt: fileURL)
        }
    }

    private static func isMP3(header: [UInt8], ext: String) -> Bool {
        if header.count >= 3 && header[0] == 0x49 && header[1] == 0x44 && header[2] == 0x33 {
            return true
        }
        if header.count >= 2 && header[0] == 0xFF && (header[1] & 0xE0) == 0xE0 {
            return true
        }
        return ext == "mp3"
    }

    private static func isM4A(header: [UInt8], ext: String) -> Bool {
        if header.count >= 8 && header[4] == 0x66 && header[5] == 0x74 && header[6] == 0x79 && header[7] == 0x70 {
            return true
        }
        return ext == "m4a" || ext == "mp4" || ext == "aac"
    }

    private static func isFLAC(header: [UInt8], ext: String) -> Bool {
        if header.count >= 4 && header[0] == 0x66 && header[1] == 0x4C && header[2] == 0x61 && header[3] == 0x43 {
            return true
        }
        return ext == "flac"
    }

    private static func readHeaderBytes(at url: URL, count: Int) -> [UInt8] {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let data = try? handle.read(upToCount: count) else {
            return []
        }
        try? handle.close()
        return [UInt8](data)
    }
}
