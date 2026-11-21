import Foundation
import Darwin

enum AudioFileValidator {
    static func isValidAudioFile(at url: URL) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64,
              size >= 4096 else {
            return false
        }

        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        guard validateFileIntegrity(fd: fd, size: size) else { return false }
        return validateHeader(fd: fd)
    }

    private static func validateFileIntegrity(fd: Int32, size: Int64) -> Bool {
        let holeOffset = lseek(fd, 0, SEEK_HOLE)
        if holeOffset >= 0 && holeOffset < size {
            return false
        }

        guard size > 65536 else { return true }
        let step = size / 8
        let sampleOffsets = (1...7).map { Int64($0) * step } + [max(0, size - 2048)]
        var sample = [UInt8](repeating: 0, count: 512)
        for offset in sampleOffsets {
            let readCount = pread(fd, &sample, 512, off_t(offset))
            if readCount == 512 && sample.allSatisfy({ $0 == 0 }) {
                return false
            }
        }
        return true
    }

    private static func validateHeader(fd: Int32) -> Bool {
        var header = [UInt8](repeating: 0, count: 64)
        let bytesRead = pread(fd, &header, 64, 0)
        guard bytesRead >= 12, !header.prefix(bytesRead).allSatisfy({ $0 == 0 }) else {
            return false
        }

        if let first = header.prefix(bytesRead).first(where: {
            $0 != 0x20 && $0 != 0x09 && $0 != 0x0A && $0 != 0x0D
        }), first == 0x3C || first == 0x7B || first == 0x5B {
            return false
        }

        return matchAudioHeader(header)
    }

    private static func matchAudioHeader(_ b: [UInt8]) -> Bool {
        matchStandardAudioHeader(b) || matchExtendedAudioHeader(b)
    }

    private static func matchStandardAudioHeader(_ b: [UInt8]) -> Bool {
        if b[0] == 0x49 && b[1] == 0x44 && b[2] == 0x33 { return true }
        if b[0] == 0xFF && (b[1] & 0xE0) == 0xE0 { return true }
        if b[0] == 0x4F && b[1] == 0x67 && b[2] == 0x67 && b[3] == 0x53 { return true }
        if b[0] == 0x66 && b[1] == 0x4C && b[2] == 0x61 && b[3] == 0x43 { return true }
        if b.count >= 8 && b[4] == 0x66 && b[5] == 0x74 && b[6] == 0x79 && b[7] == 0x70 { return true }
        if b.count >= 12 && b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46
            && b[8] == 0x57 && b[9] == 0x41 && b[10] == 0x56 && b[11] == 0x45 { return true }
        return false
    }

    private static func matchExtendedAudioHeader(_ b: [UInt8]) -> Bool {
        if b.count >= 12 && b[0] == 0x46 && b[1] == 0x4F && b[2] == 0x52 && b[3] == 0x4D
            && b[8] == 0x41 && b[9] == 0x49 && b[10] == 0x46 && (b[11] == 0x46 || b[11] == 0x43) { return true }
        if b.count >= 4 && b[0] == 0x4D && b[1] == 0x41 && b[2] == 0x43 && b[3] == 0x20 { return true }
        if b.count >= 4 && b[0] == 0x1A && b[1] == 0x45 && b[2] == 0xDF && b[3] == 0xA3 { return true }
        if b.count >= 4 && b[0] == 0x63 && b[1] == 0x61 && b[2] == 0x66 && b[3] == 0x66 { return true }
        if b.count >= 4 && b[0] == 0x77 && b[1] == 0x76 && b[2] == 0x70 && b[3] == 0x6B { return true }
        if b.count >= 4 && b[0] == 0x54 && b[1] == 0x54 && b[2] == 0x41 && (b[3] == 0x31 || b[3] == 0x32) { return true }
        return false
    }
}
