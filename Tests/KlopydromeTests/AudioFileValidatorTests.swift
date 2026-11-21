import XCTest
@testable import Klopydrome
import Darwin

final class AudioFileValidatorTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioFileValidatorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeFile(name: String, content: Data) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try content.write(to: url)
        return url
    }

    func testRejectsFilesSmallerThan4KB() throws {
        let url = try makeFile(name: "tiny.mp3", content: Data("ID3".utf8))
        XCTAssertFalse(AudioFileValidator.isValidAudioFile(at: url))
    }

    func testRejectsHTMLErrorPages() throws {
        var htmlData = Data("<!DOCTYPE html><html><body>502 Bad Gateway</body></html>".utf8)
        htmlData.append(Data(repeating: 0x20, count: 5000))
        let url = try makeFile(name: "error.mp3", content: htmlData)
        XCTAssertFalse(AudioFileValidator.isValidAudioFile(at: url))
    }

    func testRejectsJSONErrorResponses() throws {
        var jsonData = Data("{\"error\": {\"code\": 500, \"message\": \"Internal Server Error\"}}".utf8)
        jsonData.append(Data(repeating: 0x20, count: 5000))
        let url = try makeFile(name: "error.json", content: jsonData)
        XCTAssertFalse(AudioFileValidator.isValidAudioFile(at: url))
    }

    func testRejectsAllZeroBlocks() throws {
        let zeros = Data(repeating: 0, count: 65536)
        let url = try makeFile(name: "zeros.opus", content: zeros)
        XCTAssertFalse(AudioFileValidator.isValidAudioFile(at: url))
    }

    func testRejectsSparseHoles() throws {
        let url = tempDir.appendingPathComponent("sparse.opus")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        // Write valid OggS header
        var head = Data([0x4F, 0x67, 0x67, 0x53, 0x00, 0x02])
        head.append(Data(repeating: 0xAA, count: 4096))
        try handle.write(contentsOf: head)
        // Seek past EOF creating a sparse hole
        try handle.seek(toOffset: 500_000)
        try handle.write(contentsOf: head)
        try handle.close()

        XCTAssertFalse(AudioFileValidator.isValidAudioFile(at: url), "Sparse file with SEEK_HOLE must be rejected")
    }

    func testRejectsZeroEntropyBlocksInMiddle() throws {
        var data = Data([0x4F, 0x67, 0x67, 0x53]) // OggS
        data.append(Data(repeating: 0x55, count: 30000))
        // Insert 12 KB zeros in the middle (spans across midpoint sample)
        data.append(Data(repeating: 0x00, count: 12288))
        data.append(Data(repeating: 0x55, count: 30000))
        let url = try makeFile(name: "zero_gap.opus", content: data)
        XCTAssertFalse(AudioFileValidator.isValidAudioFile(at: url))
    }

    func testAcceptsValidContainers() throws {
        // 1. ID3 MP3
        var id3 = Data([0x49, 0x44, 0x33, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        id3.append(Data(repeating: 0xAA, count: 10000))
        let id3URL = try makeFile(name: "valid.mp3", content: id3)
        XCTAssertTrue(AudioFileValidator.isValidAudioFile(at: id3URL))

        // 2. MPEG Sync Frame (MP3 without ID3)
        var mpeg = Data([0xFF, 0xFB, 0x90, 0x64, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        mpeg.append(Data(repeating: 0xBB, count: 10000))
        let mpegURL = try makeFile(name: "valid_raw.mp3", content: mpeg)
        XCTAssertTrue(AudioFileValidator.isValidAudioFile(at: mpegURL))

        // 3. OggS (Opus / Vorbis)
        var ogg = Data([0x4F, 0x67, 0x67, 0x53, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        ogg.append(Data(repeating: 0xCC, count: 10000))
        let oggURL = try makeFile(name: "valid.opus", content: ogg)
        XCTAssertTrue(AudioFileValidator.isValidAudioFile(at: oggURL))

        // 4. FLAC
        var flac = Data([0x66, 0x4C, 0x61, 0x43, 0x00, 0x00, 0x00, 0x22, 0x00, 0x00, 0x00, 0x00])
        flac.append(Data(repeating: 0xDD, count: 10000))
        let flacURL = try makeFile(name: "valid.flac", content: flac)
        XCTAssertTrue(AudioFileValidator.isValidAudioFile(at: flacURL))

        // 5. M4A (ftyp)
        var m4a = Data([0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70, 0x4D, 0x34, 0x41, 0x20])
        m4a.append(Data(repeating: 0xEE, count: 10000))
        let m4aURL = try makeFile(name: "valid.m4a", content: m4a)
        XCTAssertTrue(AudioFileValidator.isValidAudioFile(at: m4aURL))

        // 6. RIFF WAVE
        var wav = Data([0x52, 0x49, 0x46, 0x46, 0x24, 0x08, 0x00, 0x00, 0x57, 0x41, 0x56, 0x45])
        wav.append(Data(repeating: 0x11, count: 10000))
        let wavURL = try makeFile(name: "valid.wav", content: wav)
        XCTAssertTrue(AudioFileValidator.isValidAudioFile(at: wavURL))

        // 7. AIFF
        var aiff = Data([0x46, 0x4F, 0x52, 0x4D, 0x00, 0x00, 0x10, 0x00, 0x41, 0x49, 0x46, 0x46])
        aiff.append(Data(repeating: 0x22, count: 10000))
        let aiffURL = try makeFile(name: "valid.aiff", content: aiff)
        XCTAssertTrue(AudioFileValidator.isValidAudioFile(at: aiffURL))

        // 8. APE
        var ape = Data([0x4D, 0x41, 0x43, 0x20, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        ape.append(Data(repeating: 0x33, count: 10000))
        let apeURL = try makeFile(name: "valid.ape", content: ape)
        XCTAssertTrue(AudioFileValidator.isValidAudioFile(at: apeURL))

        // 9. MKA / WebM
        var mka = Data([0x1A, 0x45, 0xDF, 0xA3, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        mka.append(Data(repeating: 0x44, count: 10000))
        let mkaURL = try makeFile(name: "valid.mka", content: mka)
        XCTAssertTrue(AudioFileValidator.isValidAudioFile(at: mkaURL))

        // 10. CAF
        var caf = Data([0x63, 0x61, 0x66, 0x66, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        caf.append(Data(repeating: 0x55, count: 10000))
        let cafURL = try makeFile(name: "valid.caf", content: caf)
        XCTAssertTrue(AudioFileValidator.isValidAudioFile(at: cafURL))

        // 11. WavPack
        var wvpk = Data([0x77, 0x76, 0x70, 0x6B, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        wvpk.append(Data(repeating: 0x66, count: 10000))
        let wvpkURL = try makeFile(name: "valid.wv", content: wvpk)
        XCTAssertTrue(AudioFileValidator.isValidAudioFile(at: wvpkURL))

        // 12. TTA
        var tta = Data([0x54, 0x54, 0x41, 0x31, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        tta.append(Data(repeating: 0x77, count: 10000))
        let ttaURL = try makeFile(name: "valid.tta", content: tta)
        XCTAssertTrue(AudioFileValidator.isValidAudioFile(at: ttaURL))
    }
}
