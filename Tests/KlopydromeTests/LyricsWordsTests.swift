import XCTest
import NavidromeClient
@testable import Klopydrome

@MainActor
final class LyricsWordsTests: XCTestCase {

    func testPlainLineBecomesSingleWordWithLineStart() {
        let words = WordSyncParser.parse("Hello world", lineStart: 12.5)
        XCTAssertEqual(words.count, 1)
        XCTAssertEqual(words[0].text, "Hello world")
        XCTAssertEqual(words[0].start, 12.5)
    }

    func testPlainLineWithNilStartDefaultsToZero() {
        let words = WordSyncParser.parse("No timing", lineStart: nil)
        XCTAssertEqual(words[0].start, 0)
    }

    func testWordMarkersSplitLineAndKeepSpacing() {
        let value = "I <00:10.20>love <00:10.50>coding <00:10.90>here."
        let words = WordSyncParser.parse(value, lineStart: 10.0)
        XCTAssertEqual(words.count, 4)
        XCTAssertEqual(words.map(\.text), ["I ", "love ", "coding ", "here."])
        XCTAssertEqual(words[0].start, 10.0, accuracy: 0.001)
        XCTAssertEqual(words[1].start, 10.2, accuracy: 0.001)
        XCTAssertEqual(words[2].start, 10.5, accuracy: 0.001)
        XCTAssertEqual(words[3].start, 10.9, accuracy: 0.001)
        // Rejoining must reproduce the original text minus the markers.
        XCTAssertEqual(words.map(\.text).joined(), "I love coding here.")
    }

    func testMarkerAtVeryStart() {
        let words = WordSyncParser.parse("<00:05.00>go", lineStart: nil)
        XCTAssertEqual(words.count, 1)
        XCTAssertEqual(words[0].text, "go")
        XCTAssertEqual(words[0].start, 5.0, accuracy: 0.001)
    }

    /// Real Enhanced-LRC payload from a Navidrome `line.value` (old server
    /// version: word timing lives INSIDE the text, not in `cueLine`). The
    /// marker clock must agree with the line's recorded start (31610 ms).
    func testRealEnhancedLrcInlineMarkersParse() {
        let value = "<00:31.61>Did <00:31.96>it <00:32.18>real<00:32.30>ly <00:32.53>hap<00:32.84>pen"
        let words = WordSyncParser.parse(value, lineStart: 31.61)
        XCTAssertEqual(words.count, 6)
        XCTAssertEqual(words.map(\.text).joined(), "Did it really happen")
        // First marker matches the line start exactly.
        XCTAssertEqual(words[0].start, 31.61, accuracy: 0.001)
        XCTAssertEqual(words[1].start, 31.96, accuracy: 0.001)
        XCTAssertEqual(words[2].start, 32.18, accuracy: 0.001)
        XCTAssertEqual(words[3].start, 32.30, accuracy: 0.001)
        // Syllables split across markers (real→real+ly) stay in order.
        XCTAssertEqual(words[4].start, 32.53, accuracy: 0.001)
        XCTAssertEqual(words[5].start, 32.84, accuracy: 0.001)
    }

    /// A real line that begins with the marker before ANY plain text: the
    /// pre-marker chunk must not produce an empty first word.
    func testRealEnhancedLrcMarkerFirstChunkSkipped() {
        let value = "<00:33.15>Or <00:33.49>were"
        let words = WordSyncParser.parse(value, lineStart: 33.15)
        XCTAssertEqual(words.map(\.text), ["Or ", "were"])
        XCTAssertEqual(words.map(\.start), [33.15, 33.49])
    }

    func testMillisecondsMarkerWithoutFraction() {
        let words = WordSyncParser.parse("pre <01:05>post", lineStart: 0)
        XCTAssertEqual(words.count, 2)
        XCTAssertEqual(words[1].start, 65.0, accuracy: 0.001)
    }

    func testMalformedMarkerKeepsPreviousStart() {
        let words = WordSyncParser.parse("a <oops>b", lineStart: 3.0)
        XCTAssertEqual(words.count, 2)
        XCTAssertEqual(words[0].start, 3.0)
        XCTAssertEqual(words[1].start, 3.0)
    }

    // MARK: Sync correction (LyricsStore timeOffsets)

    func testEmptyStoreHasZeroOffset() {
        let store = LyricsStore()
        XCTAssertEqual(store.timeOffsetSeconds, 0, accuracy: 0.001)
    }

    func testStoredOffsetIsReadBackAfterSet() {
        let store = LyricsStore()
        store.loadedForSongID = "song-1"
        store.timeOffsetSeconds = 2.5
        XCTAssertEqual(store.timeOffsetSeconds, 2.5, accuracy: 0.001)
        store.loadedForSongID = "song-2"
        XCTAssertEqual(store.timeOffsetSeconds, 0, accuracy: 0.001)
    }

    /// Contract used by LyricsView: it feeds `currentTime + timeOffsetSeconds`
    /// into `activeLineIndex(at:)`. Positive offset → highlight EARLIER: with
    /// +1 s the view probes a line starting at 10 s as soon as the audio
    /// reaches 9 s, whereas the raw lookup would wait until 10 s.
    func testPositiveOffsetActivatesLineEarlier() {
        let store = LyricsStore()
        store.loadedForSongID = "song-1"
        store.syncedLines = [
            SyncedLine(start: 10_000, value: "ten"),
            SyncedLine(start: 20_000, value: "twenty")
        ]
        let offset: Double = 1.0
        // Raw lookup at audio 9.2 s → no line is active yet (before `ten`).
        XCTAssertNil(store.activeLineIndex(at: 9.2))
        // Shifted lookup the view performs at the same audio time:
        // 9.2 + 1.0 = 10.2 s → the 10 s line is now active (highlight earlier).
        XCTAssertEqual(store.activeLineIndex(at: 9.2 + offset), 0)
        // Two lines later: 19.2 + 1.0 = 20.2 s → 20 s line active already at
        // audio 19.2 s.
        XCTAssertEqual(store.activeLineIndex(at: 19.2 + offset), 1)
    }

    /// Negative offset pushes the highlight LATER: at audio 20.5 s the view
    /// probes 20.5 - 1 = 19.5 s, so the 20 s line is NOT active yet.
    func testNegativeOffsetShiftsHighlightLater() {
        let store = LyricsStore()
        store.loadedForSongID = "song-1"
        store.syncedLines = [
            SyncedLine(start: 10_000, value: "ten"),
            SyncedLine(start: 20_000, value: "twenty")
        ]
        let offset: Double = -1.0
        // Raw lookup at audio 20.5 s would already pick the 20 s line.
        XCTAssertEqual(store.activeLineIndex(at: 20.5), 1)
        // Shifted lookup: 20.5 - 1 = 19.5 s → still on the 10 s line.
        XCTAssertEqual(store.activeLineIndex(at: 20.5 + offset), 0)
    }

    // MARK: Rate (stretch) correction — LyricsStore timeRates

    func testEmptyStoreHasUnityRate() {
        let store = LyricsStore()
        XCTAssertEqual(store.timeRate, 1.0, accuracy: 0.001)
    }

    func testStoredRateIsReadBackAfterSet() {
        let store = LyricsStore()
        store.loadedForSongID = "song-1"
        store.timeRate = 1.05
        XCTAssertEqual(store.timeRate, 1.05, accuracy: 0.001)
        store.loadedForSongID = "song-2"
        XCTAssertEqual(store.timeRate, 1.0, accuracy: 0.001)
    }

    /// Contract used by LyricsView: it feeds `currentTime * rate + offset`
    /// into `activeLineIndex(at:)`. A rate > 1 makes the highlight advance
    /// FASTER than the audio, so it activates lines progressively earlier —
    /// the fix for lyrics that drift late over the song.
    func testRateAboveOneActivatesLinesEarlier() {
        let store = LyricsStore()
        store.loadedForSongID = "song-1"
        store.syncedLines = [
            SyncedLine(start: 10_000, value: "ten"),
            SyncedLine(start: 20_000, value: "twenty")
        ]
        let rate: Double = 2.0
        // Raw lookup at audio 9.5 s → no line active yet.
        XCTAssertNil(store.activeLineIndex(at: 9.5))
        // Scaled lookup the view performs at the same audio time:
        // 9.5 * 2 = 19 s → the 10 s line is active already.
        XCTAssertEqual(store.activeLineIndex(at: 9.5 * rate), 0)
        // A bit further: 10.5 * 2 = 21 s → the 20 s line activates at audio
        // 10.5 s instead of 20 s.
        XCTAssertEqual(store.activeLineIndex(at: 10.5 * rate), 1)
    }

    /// Rate < 1 slows the highlight: at audio 30 s the view probes 30 * 0.5
    /// = 15 s, so the 20 s line is NOT active yet even though raw playback
    /// would have reached it.
    func testRateBelowOneShiftsHighlightLater() {
        let store = LyricsStore()
        store.loadedForSongID = "song-1"
        store.syncedLines = [
            SyncedLine(start: 10_000, value: "ten"),
            SyncedLine(start: 20_000, value: "twenty")
        ]
        let rate: Double = 0.5
        // Raw lookup at audio 30 s picks the 20 s line.
        XCTAssertEqual(store.activeLineIndex(at: 30), 1)
        // Scaled lookup: 30 * 0.5 = 15 s → still on the 10 s line.
        XCTAssertEqual(store.activeLineIndex(at: 30 * rate), 0)
    }

    // MARK: LRC text parsing (`LrcTextParser`) — classic-endpoint fallback

    /// `[mm:ss.xx]` markers become millisecond starts.
    func testLrcParsesTimestampsToMilliseconds() {
        let lines = LrcTextParser.parse("[00:18.80]Line one\n[00:28.01]Line two")
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].start, 18_800)
        XCTAssertEqual(lines[0].value, "Line one")
        XCTAssertEqual(lines[1].start, 28_010)
        XCTAssertEqual(lines[1].value, "Line two")
    }

    /// LRC fractions of 1, 2 and 3 digits all normalize to milliseconds.
    func testLrcFractionDigitsNormalize() {
        let lines = LrcTextParser.parse("[00:01.8]a\n[00:02.80]b\n[00:03.800]c")
        XCTAssertEqual(lines.map(\.start), [1_800, 2_800, 3_800])
    }

    /// A single line may carry several timestamps; each becomes a synced line.
    func testLrcMultipleTimestampsPerLine() {
        let lines = LrcTextParser.parse("[00:10.00][00:15.00]repeat")
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines.map(\.start), [10_000, 15_000])
        XCTAssertEqual(lines.map(\.value), ["repeat", "repeat"])
    }

    /// Plain text (no markers) yields no synced lines — the caller falls back
    /// to showing it as-is.
    func testLrcPlainTextYieldsNothing() {
        let lines = LrcTextParser.parse("Just words\nacross two lines")
        XCTAssertTrue(lines.isEmpty)
    }

    /// Metadata tags and blank lines are dropped.
    func testLrcDropsMetadataAndBlankLines() {
        let lines = LrcTextParser.parse("[ar:Artist]\n[ti:Title]\n\n[00:05.00]real")
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].start, 5_000)
        XCTAssertEqual(lines[0].value, "real")
    }

    /// `[offset:-100]` (per LRC spec) shifts the highlight 100 ms LATER: the
    /// probe is `audio + offset`, so `start - offset` bakes it into the lines.
    func testLrcOffsetShiftsStarts() {
        let lines = LrcTextParser.parse("[offset:-100]\n[00:18.80]Line one")
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].start, 18_900)
    }

    /// A positive offset shifts the highlight EARLIER (start - offset).
    func testLrcPositiveOffsetShiftsStarts() {
        let lines = LrcTextParser.parse("[offset:+500]\n[00:18.80]Line one")
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].start, 18_300)
    }

    // MARK: `LyricsEntry.offset` decoding (OpenSubsonic structured lyrics)

    func testLyricsEntryDecodesOffsetWhenPresent() throws {
        let json = Data("""
        {"synced": true, "offset": -100, "line": [{"start": 18800, "value": "a"}]}
        """.utf8)
        let entry = try JSONDecoder().decode(LyricsEntry.self, from: json)
        XCTAssertEqual(entry.offset, -100)
        XCTAssertEqual(entry.line?.first?.start, 18_800)
    }

    func testLyricsEntryDecodesWithoutOffset() throws {
        let json = Data("""
        {"synced": true, "line": [{"start": 18800, "value": "a"}]}
        """.utf8)
        let entry = try JSONDecoder().decode(LyricsEntry.self, from: json)
        XCTAssertNil(entry.offset)
        XCTAssertEqual(entry.line?.first?.start, 18_800)
    }

    // MARK: Unsynced structured lyrics → plain text fallback

    func testPlainTextJoinsUnsyncedStructuredLines() {
        let entries = [
            LyricsEntry(synced: false, line: [
                SyncedLine(value: "First line"),
                SyncedLine(value: "Second line")
            ])
        ]
        XCTAssertEqual(LyricsStore.plainText(from: entries), "First line\nSecond line")
    }

    func testPlainTextSkipsBlankLines() {
        let entries = [LyricsEntry(line: [SyncedLine(value: "  "), SyncedLine(value: "real")])]
        XCTAssertEqual(LyricsStore.plainText(from: entries), "real")
    }

    func testPlainTextIsNilWhenNoText() {
        XCTAssertNil(LyricsStore.plainText(from: nil))
        XCTAssertNil(LyricsStore.plainText(from: []))
        // Entries with no line values carry no text either.
        let empty = [LyricsEntry(synced: true, line: [SyncedLine(start: 1_000)])]
        XCTAssertNil(LyricsStore.plainText(from: empty))
    }

    // MARK: Active line before the first line (Apple Music semantics)

    /// No line is highlighted until the first line's timestamp arrives; the
    /// stored lines themselves stay dim/future instead of pretending line 0 is
    /// active at t=0.
    func testNoActiveLineBeforeFirstLine() {
        let store = LyricsStore()
        store.loadedForSongID = "song-1"
        store.syncedLines = [
            SyncedLine(start: 10_000, value: "ten"),
            SyncedLine(start: 20_000, value: "twenty")
        ]
        XCTAssertNil(store.activeLineIndex(at: 0))
        XCTAssertNil(store.activeLineIndex(at: 9.999))
        XCTAssertEqual(store.activeLineIndex(at: 10), 0)
        XCTAssertEqual(store.activeLineIndex(at: 25), 1)
    }

    // MARK: Word cues (`LyricsCueLine` / `LyricsCue`) decoding

    func testLyricsEntryDecodesCueLines() throws {
        let json = Data("""
        {
          "synced": true,
          "line": [{"start": 10000, "value": "hello world"}],
          "cueLine": [{
            "index": 0, "start": 10000, "end": 15000, "value": "hello world", "agentId": "main",
            "cue": [
              {"start": 10000, "end": 10700, "byteStart": 0, "byteEnd": 5, "value": "hello"},
              {"start": 10700, "byteStart": 6, "byteEnd": 10, "value": "world"}
            ]
          }]
        }
        """.utf8)
        let entry = try JSONDecoder().decode(LyricsEntry.self, from: json)
        let cueLine = entry.cueLine?.first
        XCTAssertEqual(cueLine?.index, 0)
        XCTAssertEqual(cueLine?.agentId, "main")
        XCTAssertEqual(cueLine?.cue?.count, 2)
        XCTAssertEqual(cueLine?.cue?.first?.start, 10_000)
        XCTAssertEqual(cueLine?.cue?.first?.end, 10_700)
        // A cue without `end` keeps it nil (server omits it when unresolvable).
        XCTAssertEqual(cueLine?.cue?.last?.start, 10_700)
        XCTAssertNil(cueLine?.cue?.last?.end)
    }

    // MARK: `wordsByLine` construction

    func testWordsByLineBuildsFromCueLines() throws {
        let entry = LyricsEntry(
            synced: true,
            line: [
                SyncedLine(start: 10_000, value: "line zero"),
                SyncedLine(start: 20_000, value: "line one")
            ],
            cueLine: [
                LyricsCueLine(index: 0, start: 10_000, end: 14_000, value: "line zero", cue: [
                    LyricsCue(start: 10_000, end: 11_000, byteStart: 0, byteEnd: 5, value: "line "),
                    LyricsCue(start: 11_000, end: 14_000, byteStart: 6, byteEnd: 9, value: "zero")
                ]),
                // Second agent sharing index 0 → skipped (primary vocal first).
                LyricsCueLine(index: 0, start: 10_000, end: 14_000, value: "line zero", cue: [
                    LyricsCue(start: 10_000, value: "backup")
                ]),
                // Out-of-range index → ignored.
                LyricsCueLine(index: 99, start: 0, end: 0, value: "x", cue: [
                    LyricsCue(start: 0, value: "y")
                ])
            ],
            offset: 500
        )
        let words = LyricsStore.wordsByLine(from: entry, offset: 500, lineCount: 2)
        XCTAssertEqual(words.count, 1)
        let lineWords = try XCTUnwrap(words[0])
        XCTAssertEqual(lineWords.count, 2)
        XCTAssertEqual(lineWords[0].text, "line ")
        // ms → seconds AND the entry offset baked in: (10000-500)/1000.
        XCTAssertEqual(lineWords[0].start, 9.5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(lineWords[0].end), 10.5, accuracy: 0.001)
        XCTAssertEqual(lineWords[1].start, 10.5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(lineWords[1].end), 13.5, accuracy: 0.001)
    }

    func testWordsByLineEmptyWithoutCues() {
        let entry = LyricsEntry(synced: true, line: [SyncedLine(start: 1_000, value: "x")])
        XCTAssertTrue(LyricsStore.wordsByLine(from: entry, offset: nil, lineCount: 1).isEmpty)
    }
    // MARK: Async loading ownership

    func testLyricsResultAppliesOnlyToItsStillCurrentSong() {
        XCTAssertTrue(LyricsStore.shouldApplyLoadResult(
            requestedSongID: "song-a",
            loadedForSongID: "song-a",
            taskCancelled: false
        ))
        XCTAssertFalse(LyricsStore.shouldApplyLoadResult(
            requestedSongID: "song-a",
            loadedForSongID: "song-b",
            taskCancelled: false
        ))
    }

    func testCancelledLyricsTaskCannotApplyItsResult() {
        XCTAssertFalse(LyricsStore.shouldApplyLoadResult(
            requestedSongID: "song-a",
            loadedForSongID: "song-a",
            taskCancelled: true
        ))
    }

}
