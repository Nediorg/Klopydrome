import AVFoundation
import Foundation
import XCTest
@testable import Klopydrome
@testable import NavidromeClient

final class TrackMetadataInjectionTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrackMetadataTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        super.tearDown()
    }

    func testID3v2TagWriterInjectsFramesAndCoverArt() throws {
        let mp3URL = tempDirectory.appendingPathComponent("test_track.mp3")
        let dummyAudio = makeSyntheticMP3Data(frameCount: 10)
        try dummyAudio.write(to: mp3URL)

        let dummyCover = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46])
        let metadata = AudioTagMetadata(
            title: "Synthetic Title Alpha",
            artist: "Synthetic Artist Beta",
            albumArtist: "Synthetic Artist Beta",
            album: "Synthetic Album Gamma",
            genre: "Electronic",
            year: 2025,
            trackNumber: 4,
            discNumber: 1,
            bpm: 128,
            coverArtData: dummyCover
        )

        try ID3v2TagWriter.write(metadata, toMP3At: mp3URL)

        let taggedData = try Data(contentsOf: mp3URL)
        XCTAssertGreaterThan(taggedData.count, dummyAudio.count)
        XCTAssertEqual(taggedData.prefix(3), Data([0x49, 0x44, 0x33])) // "ID3"
        XCTAssertEqual(taggedData[3], 0x03) // ID3v2.3

        XCTAssertTrue(taggedData.range(of: Data("TIT2".utf8)) != nil)
        XCTAssertTrue(taggedData.range(of: Data("TPE1".utf8)) != nil)
        XCTAssertTrue(taggedData.range(of: Data("TALB".utf8)) != nil)
        XCTAssertTrue(taggedData.range(of: Data("TYER".utf8)) != nil)
        XCTAssertTrue(taggedData.range(of: Data("TRCK".utf8)) != nil)
        XCTAssertTrue(taggedData.range(of: Data("TPOS".utf8)) != nil)
        XCTAssertTrue(taggedData.range(of: Data("TCON".utf8)) != nil)
        XCTAssertTrue(taggedData.range(of: Data("TBPM".utf8)) != nil)
        XCTAssertTrue(taggedData.range(of: Data("APIC".utf8)) != nil)
        XCTAssertTrue(taggedData.range(of: dummyCover) != nil)
    }

    func testID3v2TagWriterReplacesExistingTagWithoutDuplication() throws {
        let mp3URL = tempDirectory.appendingPathComponent("replace_tag.mp3")
        let dummyAudio = makeSyntheticMP3Data(frameCount: 8)
        try dummyAudio.write(to: mp3URL)

        let initialMeta = AudioTagMetadata(
            title: "Track Title 001",
            artist: "Original Artist"
        )
        try ID3v2TagWriter.write(initialMeta, toMP3At: mp3URL)
        let firstSize = try FileManager.default.attributesOfItem(atPath: mp3URL.path)[.size] as? Int ?? 0

        let updatedMeta = AudioTagMetadata(
            title: "Track Title 002",
            artist: "Original Artist"
        )
        try ID3v2TagWriter.write(updatedMeta, toMP3At: mp3URL)
        let secondSize = try FileManager.default.attributesOfItem(atPath: mp3URL.path)[.size] as? Int ?? 0

        let taggedData = try Data(contentsOf: mp3URL)
        let tit2Matches = findAllOccurrences(of: Data("TIT2".utf8), in: taggedData)
        XCTAssertEqual(tit2Matches.count, 1)
        XCTAssertEqual(firstSize, secondSize)
        XCTAssertTrue(taggedData.range(of: "Track Title 002".data(using: .utf16LittleEndian)!) != nil)
        XCTAssertTrue(taggedData.range(of: "Track Title 001".data(using: .utf16LittleEndian)!) == nil)
    }

    func testM4AMetadataWriterInjectsITunesAtoms() async throws {
        let m4aURL = tempDirectory.appendingPathComponent("test_track.m4a")
        try await createSilentM4A(at: m4aURL)

        let dummyCover = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46])
        let metadata = AudioTagMetadata(
            title: "M4A Title Alpha",
            artist: "M4A Artist Beta",
            album: "M4A Album Gamma",
            genre: "Jazz",
            year: 2024,
            trackNumber: 5,
            discNumber: 2,
            coverArtData: dummyCover
        )

        try await M4AMetadataWriter.write(metadata, toM4AAt: m4aURL)

        let asset = AVURLAsset(url: m4aURL)
        let items = try await asset.load(.metadata)
        let titles = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .iTunesMetadataSongName)
        let artists = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .iTunesMetadataArtist)
        let albums = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .iTunesMetadataAlbum)
        let covers = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .iTunesMetadataCoverArt)

        let loadedTitle = try await titles.first?.load(.stringValue)
        let loadedArtist = try await artists.first?.load(.stringValue)
        let loadedAlbum = try await albums.first?.load(.stringValue)
        let loadedCover = try await covers.first?.load(.dataValue)

        XCTAssertEqual(loadedTitle, "M4A Title Alpha")
        XCTAssertEqual(loadedArtist, "M4A Artist Beta")
        XCTAssertEqual(loadedAlbum, "M4A Album Gamma")
        XCTAssertEqual(loadedCover, dummyCover)
    }

    func testFLACTagWriterInjectsVorbisCommentAndPictureBlock() throws {
        let flacURL = tempDirectory.appendingPathComponent("test_track.flac")
        let dummyFLAC = makeSyntheticFLACData()
        try dummyFLAC.write(to: flacURL)

        let dummyCover = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let metadata = AudioTagMetadata(
            title: "Synthetic FLAC Title",
            artist: "Synthetic FLAC Artist",
            album: "Synthetic FLAC Album",
            genre: "Ambient",
            year: 2026,
            trackNumber: 2,
            discNumber: 1,
            coverArtData: dummyCover
        )

        try FLACTagWriter.write(metadata, toFLACAt: flacURL)

        let taggedData = try Data(contentsOf: flacURL)
        XCTAssertEqual(taggedData.prefix(4), Data([0x66, 0x4C, 0x61, 0x43])) // "fLaC"
        XCTAssertTrue(taggedData.range(of: Data("TITLE=Synthetic FLAC Title".utf8)) != nil)
        XCTAssertTrue(taggedData.range(of: Data("ARTIST=Synthetic FLAC Artist".utf8)) != nil)
        XCTAssertTrue(taggedData.range(of: Data("ALBUM=Synthetic FLAC Album".utf8)) != nil)
        XCTAssertTrue(taggedData.range(of: Data("GENRE=Ambient".utf8)) != nil)
        XCTAssertTrue(taggedData.range(of: Data("DATE=2026".utf8)) != nil)
        XCTAssertTrue(taggedData.range(of: Data("TRACKNUMBER=2".utf8)) != nil)
        XCTAssertTrue(taggedData.range(of: dummyCover) != nil)
    }

    func testAudioMetadataWriterDispatchesCorrectly() async throws {
        let mp3URL = tempDirectory.appendingPathComponent("dispatch.mp3")
        try makeSyntheticMP3Data(frameCount: 5).write(to: mp3URL)

        let metadata = AudioTagMetadata(title: "Dispatched Title", artist: "Dispatched Artist")
        try await AudioMetadataWriter.inject(metadata, into: mp3URL)

        let data = try Data(contentsOf: mp3URL)
        XCTAssertEqual(data.prefix(3), Data([0x49, 0x44, 0x33]))
    }

    private func makeSyntheticMP3Data(frameCount: Int) -> Data {
        var data = Data()
        for _ in 0..<frameCount {
            data.append(contentsOf: [0xFF, 0xFB, 0x90, 0x64])
            data.append(Data(repeating: 0x55, count: 413))
        }
        return data
    }

    private func makeSyntheticFLACData() -> Data {
        var data = Data([0x66, 0x4C, 0x61, 0x43]) // "fLaC"
        // STREAMINFO block: header (0x80 = isLast, 0x00 = STREAMINFO, len = 34)
        data.append(contentsOf: [0x80, 0x00, 0x00, 0x22])
        data.append(Data(repeating: 0x00, count: 34))
        // Synthetic audio frames
        data.append(Data(repeating: 0xAA, count: 512))
        return data
    }

    private func createSilentM4A(at url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 64000
        ]
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings)
        input.expectsMediaDataInRealTime = false
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        if let desc = makeAudioFormatDescription(),
           let sb = makeAudioSampleBuffer(format: desc, sampleCount: 44100 / 5) {
            input.append(sb)
        }
        input.markAsFinished()
        await writer.finishWriting()
    }

    private func makeAudioFormatDescription() -> CMAudioFormatDescription? {
        var formatDesc: CMAudioFormatDescription?
        var asbd = AudioStreamBasicDescription(
            mSampleRate: 44100,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDesc
        )
        return formatDesc
    }

    private func makeAudioSampleBuffer(format: CMAudioFormatDescription, sampleCount: Int) -> CMSampleBuffer? {
        let pcmData = Data(repeating: 0, count: sampleCount * 4)
        var blockBuffer: CMBlockBuffer?
        pcmData.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: nil,
                blockLength: pcmData.count,
                blockAllocator: kCFAllocatorDefault,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: pcmData.count,
                flags: 0,
                blockBufferOut: &blockBuffer
            )
            if let bb = blockBuffer {
                CMBlockBufferReplaceDataBytes(with: base, blockBuffer: bb, offsetIntoDestination: 0, dataLength: pcmData.count)
            }
        }
        guard let bb = blockBuffer else { return nil }
        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 44100),
            presentationTimeStamp: .zero,
            decodeTimeStamp: .invalid
        )
        CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: bb,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: format,
            sampleCount: sampleCount,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        return sampleBuffer
    }

    private func findAllOccurrences(of target: Data, in source: Data) -> [Int] {
        var indices: [Int] = []
        var searchRange = 0..<source.count
        while let range = source.range(of: target, options: [], in: searchRange) {
            indices.append(range.lowerBound)
            searchRange = range.upperBound..<source.count
        }
        return indices
    }
}
