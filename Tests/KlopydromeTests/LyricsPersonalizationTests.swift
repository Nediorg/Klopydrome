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
}

// MARK: - Personalization Settings

final class LyricsPersonalizationSettingsTests: XCTestCase {
    func testServerConfigLyricsDefaults() {
        let config = ServerConfig.empty
        XCTAssertEqual(config.effectiveLyricsFontSize, .standard)
        XCTAssertEqual(config.effectiveLyricsAnimationMotion, .smooth)
        XCTAssertTrue(config.effectiveLyricsBlurEnabled)
        XCTAssertTrue(config.effectiveLyricsCountdownEnabled)
        XCTAssertEqual(config.effectiveLyricsDefaultOffset, 0.0, accuracy: 0.001)
    }

    func testServerConfigLyricsPreferencesRoundTrip() throws {
        var config = ServerConfig.empty
        config.lyricsFontSize = .large
        config.lyricsAnimationMotion = .subtle
        config.lyricsBlurEnabled = false
        config.lyricsCountdownEnabled = false
        config.lyricsDefaultOffset = 0.25

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ServerConfig.self, from: data)

        XCTAssertEqual(decoded.lyricsFontSize, .large)
        XCTAssertEqual(decoded.lyricsAnimationMotion, .subtle)
        XCTAssertEqual(decoded.lyricsBlurEnabled, false)
        XCTAssertEqual(decoded.lyricsCountdownEnabled, false)
        XCTAssertEqual(decoded.lyricsDefaultOffset ?? 0, 0.25, accuracy: 0.001)

        XCTAssertEqual(decoded.effectiveLyricsFontSize, .large)
        XCTAssertEqual(decoded.effectiveLyricsAnimationMotion, .subtle)
        XCTAssertFalse(decoded.effectiveLyricsBlurEnabled)
        XCTAssertTrue(decoded.effectiveLyricsCountdownEnabled)
        XCTAssertEqual(decoded.effectiveLyricsDefaultOffset, 0.25, accuracy: 0.001)
    }
}

// MARK: - Motion & Carousel Geometry Tests

final class LyricsMotionGeometryTests: XCTestCase {
    func testRippleReachAndProgressiveDelay() {
        XCTAssertEqual(LyricsMotionGeometry.rippleReach, 8)
        XCTAssertEqual(LyricsMotionGeometry.rippleDelay(distance: 0), 0.0, accuracy: 0.001)
        XCTAssertEqual(LyricsMotionGeometry.rippleDelay(distance: 1), 0.050, accuracy: 0.001)
        XCTAssertEqual(LyricsMotionGeometry.rippleDelay(distance: 3), 0.150, accuracy: 0.001)
        XCTAssertEqual(LyricsMotionGeometry.rippleDelay(distance: 8), 0.400, accuracy: 0.001)
        XCTAssertEqual(LyricsMotionGeometry.rippleDelay(distance: 10), 0.400, accuracy: 0.001)
    }

    func testRippleOffsetElasticWave() {
        // Active line has 0 ripple offset
        XCTAssertEqual(LyricsMotionGeometry.rippleOffset(distance: 0), 0.0, accuracy: 0.001)

        // Lines below push downwards (+Y), lines above push upwards (-Y)
        let offsetBelow1 = LyricsMotionGeometry.rippleOffset(distance: 1)
        let offsetAbove1 = LyricsMotionGeometry.rippleOffset(distance: -1)
        XCTAssertEqual(offsetBelow1, 7.0, accuracy: 0.001)
        XCTAssertEqual(offsetAbove1, -7.0, accuracy: 0.001)

        let offsetBelow2 = LyricsMotionGeometry.rippleOffset(distance: 2)
        let offsetAbove2 = LyricsMotionGeometry.rippleOffset(distance: -2)
        XCTAssertEqual(offsetBelow2, 12.0, accuracy: 0.001)
        XCTAssertEqual(offsetAbove2, -12.0, accuracy: 0.001)

        let offsetBelow4 = LyricsMotionGeometry.rippleOffset(distance: 4)
        XCTAssertEqual(offsetBelow4, 16.0, accuracy: 0.001)

        // Beyond ripple reach, ripple offset is 0
        XCTAssertEqual(LyricsMotionGeometry.rippleOffset(distance: 8), 0.0, accuracy: 0.001)
    }

    func testTotalLineOffset() {
        // Active line gets focus lift (-3.0) + 0 ripple
        XCTAssertEqual(
            LyricsMotionGeometry.totalLineOffset(distance: 0, isCurrent: true, motion: .smooth, isBrowsing: false),
            -3.0, accuracy: 0.001
        )
        // Immediate neighbors get ripple offset (+7.0 for below, -7.0 for above)
        XCTAssertEqual(
            LyricsMotionGeometry.totalLineOffset(distance: 1, isCurrent: false, motion: .smooth, isBrowsing: false),
            7.0, accuracy: 0.001
        )
        XCTAssertEqual(
            LyricsMotionGeometry.totalLineOffset(distance: -1, isCurrent: false, motion: .smooth, isBrowsing: false),
            -7.0, accuracy: 0.001
        )
        // Browsing disables offset
        XCTAssertEqual(
            LyricsMotionGeometry.totalLineOffset(distance: 1, isCurrent: false, motion: .smooth, isBrowsing: true),
            0.0, accuracy: 0.001
        )
    }

    func testPerspectiveScale() {
        // Active line expands with focus scale and crest ripple
        XCTAssertEqual(
            LyricsMotionGeometry.perspectiveScale(distance: 0, isCurrent: true, motion: .smooth),
            1.075 * 1.03, accuracy: 0.001
        )
        // Neighbor line is near neutral 1.00
        XCTAssertEqual(
            LyricsMotionGeometry.perspectiveScale(distance: 1, isCurrent: false, motion: .smooth),
            0.98 * (1.0 + 0.03 * (7.0 / 8.0)), accuracy: 0.001
        )
        // Line 8 away settles at 0.98
        XCTAssertEqual(
            LyricsMotionGeometry.perspectiveScale(distance: 8, isCurrent: false, motion: .smooth),
            0.98, accuracy: 0.001
        )
    }

    func testOptimizedLineBlur() {
        // Disabled blur
        XCTAssertEqual(
            LyricsMotionGeometry.lineBlur(
                distance: 1, isCurrent: false, isBrowsing: false, isHovering: false, blurEnabled: false
            ),
            0
        )
        // Browsing or hovering removes blur
        XCTAssertEqual(
            LyricsMotionGeometry.lineBlur(
                distance: 1, isCurrent: false, isBrowsing: true, isHovering: false, blurEnabled: true
            ),
            0
        )
        XCTAssertEqual(
            LyricsMotionGeometry.lineBlur(
                distance: 1, isCurrent: false, isBrowsing: false, isHovering: true, blurEnabled: true
            ),
            0
        )
        // Current line is never blurred
        XCTAssertEqual(
            LyricsMotionGeometry.lineBlur(
                distance: 0, isCurrent: true, isBrowsing: false, isHovering: false, blurEnabled: true
            ),
            0
        )
        // Immediate neighbors have subtle blur (0.6)
        XCTAssertEqual(
            LyricsMotionGeometry.lineBlur(
                distance: 1, isCurrent: false, isBrowsing: false, isHovering: false, blurEnabled: true
            ),
            0.6, accuracy: 0.001
        )
        // Distance 2 has soft focus blur (1.0)
        XCTAssertEqual(
            LyricsMotionGeometry.lineBlur(
                distance: 2, isCurrent: false, isBrowsing: false, isHovering: false, blurEnabled: true
            ),
            1.0, accuracy: 0.001
        )
        // Farther background lines have gentle depth-of-field blur (1.4)
        XCTAssertEqual(
            LyricsMotionGeometry.lineBlur(
                distance: 4, isCurrent: false, isBrowsing: false, isHovering: false, blurEnabled: true
            ),
            1.4, accuracy: 0.001
        )
    }
}
