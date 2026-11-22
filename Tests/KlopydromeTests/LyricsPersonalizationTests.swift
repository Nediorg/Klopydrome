import XCTest
import NavidromeClient
@testable import Klopydrome

// MARK: - Word Clusters

final class LyricsWordClusterTests: XCTestCase {
    func testEmptyWordsProduceEmptyClusters() {
        XCTAssertTrue(WordClusterBuilder.buildClusters(from: []).isEmpty)
    }

    func testPlainWordsWithSpacesFormIndividualClusters() {
        let words = [
            SyncedWord(text: "Hello ", start: 1.0),
            SyncedWord(text: "world ", start: 2.0)
        ]
        let clusters = WordClusterBuilder.buildClusters(from: words)
        XCTAssertEqual(clusters.count, 2)
        XCTAssertEqual(clusters[0].text, "Hello ")
        XCTAssertEqual(clusters[1].text, "world ")
    }

    func testSyllablesWithoutWhitespaceGroupIntoSingleWordCluster() {
        // "surren" + "der " -> "surrender "
        let words = [
            SyncedWord(text: "surren", start: 10.2),
            SyncedWord(text: "der ", start: 10.5)
        ]
        let clusters = WordClusterBuilder.buildClusters(from: words)
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters[0].text, "surrender ")
        XCTAssertEqual(clusters[0].words.count, 2)
        XCTAssertEqual(clusters[0].words[0].text, "surren")
        XCTAssertEqual(clusters[0].words[1].text, "der ")
    }

    func testMultipleMultiSyllableWordsGroupCorrectly() {
        // "Did it really happen" with "real" + "ly " and "hap" + "pen"
        let words = [
            SyncedWord(text: "Did ", start: 31.61),
            SyncedWord(text: "it ", start: 31.96),
            SyncedWord(text: "real", start: 32.18),
            SyncedWord(text: "ly ", start: 32.30),
            SyncedWord(text: "hap", start: 32.53),
            SyncedWord(text: "pen", start: 32.84)
        ]
        let clusters = WordClusterBuilder.buildClusters(from: words)
        XCTAssertEqual(clusters.count, 4)
        XCTAssertEqual(clusters.map(\.text), ["Did ", "it ", "really ", "happen"])
        XCTAssertEqual(clusters[2].words.count, 2)
        XCTAssertEqual(clusters[3].words.count, 2)
    }

    func testChunkWithInternalWhitespaceSplitsIntoSeparateClusters() {
        let words = [
            SyncedWord(text: "one two three ", start: 5.0)
        ]
        let clusters = WordClusterBuilder.buildClusters(from: words)
        XCTAssertEqual(clusters.count, 3)
        XCTAssertEqual(clusters.map(\.text), ["one ", "two ", "three "])
    }

    func testWordWhiteFadeSettlesFromWhiteToSungColor() {
        XCTAssertEqual(KaraokeLine.wordSettledOpacity(at: 9.9, wordStart: 10, sungAt: 11), 0.5)
        XCTAssertEqual(KaraokeLine.wordSettledOpacity(at: 10, wordStart: 10, sungAt: 11), 1)
        let middle = KaraokeLine.wordSettledOpacity(at: 10.14, wordStart: 10, sungAt: 11)
        XCTAssertLessThan(middle, 1)
        XCTAssertGreaterThan(middle, 0.85)
        XCTAssertEqual(KaraokeLine.wordSettledOpacity(at: 10.3, wordStart: 10, sungAt: 11), 0.85)
    }

    @MainActor
    func testLyricsRenderClockFreezesOnBuffering() async throws {
        let clock = LyricsRenderClock()
        clock.synchronize(time: 10.0, isPlaying: true, rate: 1.0)
        try await Task.sleep(nanoseconds: 50_000_000)
        let timeWhilePlaying = clock.currentTime
        XCTAssertGreaterThan(timeWhilePlaying, 10.0)
        XCTAssertTrue(clock.shouldAnimate)

        clock.synchronize(time: 10.0, isPlaying: false, rate: 1.0)
        let frozenTime = clock.currentTime
        XCTAssertFalse(clock.shouldAnimate)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(clock.currentTime, frozenTime, "Clock must freeze when buffering")
    }

    func testLineWrapWidthGuaranteesScaledFit() {
        let wrap = LyricsView.lineWrapWidth(viewportWidth: 900, horizontalPadding: 40)
        XCTAssertEqual(wrap * KaraokeLine.maxLineScale, 820, accuracy: 0.001)
        XCTAssertEqual(
            LyricsView.lineWrapWidth(viewportWidth: 10, horizontalPadding: 40),
            0,
            accuracy: 0.001
        )
    }
}
