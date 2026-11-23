import AVFoundation
import CoreMedia
import Foundation
import NavidromeClient

enum M4AMetadataWriter {
    static func write(_ metadata: AudioTagMetadata, toM4AAt url: URL) async throws {
        let asset = AVURLAsset(url: url)
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first,
              let formatDesc = try await audioTrack.load(.formatDescriptions).first else {
            return
        }

        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let writer = try AVAssetWriter(outputURL: tempURL, fileType: .m4a)
        writer.metadata = buildITunesMetadataItems(from: metadata)

        let writerInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: nil,
            sourceFormatHint: formatDesc
        )
        writerInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(writerInput) else { return }
        writer.add(writerInput)

        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
        guard reader.canAdd(readerOutput) else { return }
        reader.add(readerOutput)

        guard writer.startWriting(), reader.startReading() else {
            throw writer.error ?? reader.error ?? CocoaError(.fileWriteUnknown)
        }
        writer.startSession(atSourceTime: .zero)

        try await pipeAudioData(from: readerOutput, to: writerInput, reader: reader)
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? CocoaError(.fileWriteUnknown)
        }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
    }

    private final class PipeContext: @unchecked Sendable {
        let readerOutput: AVAssetReaderTrackOutput
        let writerInput: AVAssetWriterInput
        let reader: AVAssetReader

        init(readerOutput: AVAssetReaderTrackOutput, writerInput: AVAssetWriterInput, reader: AVAssetReader) {
            self.readerOutput = readerOutput
            self.writerInput = writerInput
            self.reader = reader
        }
    }

    private static func pipeAudioData(
        from readerOutput: AVAssetReaderTrackOutput,
        to writerInput: AVAssetWriterInput,
        reader: AVAssetReader
    ) async throws {
        let ctx = PipeContext(readerOutput: readerOutput, writerInput: writerInput, reader: reader)
        let queue = DispatchQueue(label: "app.klopydrome.m4a-tagger")
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            ctx.writerInput.requestMediaDataWhenReady(on: queue) {
                while ctx.writerInput.isReadyForMoreMediaData {
                    if let sampleBuffer = ctx.readerOutput.copyNextSampleBuffer() {
                        ctx.writerInput.append(sampleBuffer)
                    } else {
                        ctx.writerInput.markAsFinished()
                        ctx.reader.cancelReading()
                        continuation.resume()
                        break
                    }
                }
            }
        }
    }

    private static func buildITunesMetadataItems(from m: AudioTagMetadata) -> [AVMetadataItem] {
        var items: [AVMetadataItem] = []

        func addString(_ identifier: AVMetadataIdentifier, _ value: String?) {
            guard let value, !value.isEmpty else { return }
            let item = AVMutableMetadataItem()
            item.identifier = identifier
            item.value = value as NSString
            items.append(item)
        }

        addString(.iTunesMetadataSongName, m.title)
        addString(.iTunesMetadataArtist, m.artist)
        addString(.iTunesMetadataAlbumArtist, m.albumArtist)
        addString(.iTunesMetadataAlbum, m.album)
        addString(.iTunesMetadataUserGenre, m.genre)
        if let year = m.year, year > 0 {
            addString(.iTunesMetadataReleaseDate, "\(year)")
        }

        if let track = m.trackNumber, track > 0 {
            let item = AVMutableMetadataItem()
            item.identifier = .iTunesMetadataTrackNumber
            item.value = packedPairAtom(number: UInt16(clamping: track), total: 0, trailingPadding: true) as NSData
            items.append(item)
        }
        if let disc = m.discNumber, disc > 0 {
            let item = AVMutableMetadataItem()
            item.identifier = .iTunesMetadataDiscNumber
            item.value = packedPairAtom(number: UInt16(clamping: disc), total: 0, trailingPadding: false) as NSData
            items.append(item)
        }
        if let img = m.coverArtData, !img.isEmpty {
            let item = AVMutableMetadataItem()
            item.identifier = .iTunesMetadataCoverArt
            item.dataType = (m.coverArtMimeType == "image/png"
                ? kCMMetadataBaseDataType_PNG
                : kCMMetadataBaseDataType_JPEG) as String
            item.value = img as NSData
            items.append(item)
        }
        return items
    }

    private static func packedPairAtom(number: UInt16, total: UInt16, trailingPadding: Bool) -> Data {
        var data = Data([0x00, 0x00])
        var n = number.bigEndian
        var t = total.bigEndian
        data.append(Data(bytes: &n, count: 2))
        data.append(Data(bytes: &t, count: 2))
        if trailingPadding {
            data.append(contentsOf: [0x00, 0x00])
        }
        return data
    }
}
