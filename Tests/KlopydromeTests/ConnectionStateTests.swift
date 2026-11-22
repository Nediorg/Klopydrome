import XCTest
import NavidromeClient
@testable import Klopydrome

@MainActor
final class ConnectionStateTests: XCTestCase {

    func testHealthTrackerRequiresTwoServerFailuresWithinWindow() {
        var tracker = ServerHealthTracker(failureWindow: 15, tripThreshold: 2)
        let t0 = Date(timeIntervalSince1970: 1_000)

        let first = tracker.record(
            .failure(.serverError(502), message: "Bad Gateway"),
            currentState: .online,
            now: t0
        )
        XCTAssertEqual(first, .remain)

        let second = tracker.record(
            .failure(.serverUnreachable, message: "Timed out"),
            currentState: .online,
            now: t0.addingTimeInterval(5)
        )
        XCTAssertEqual(second, .tripDegraded(.serverUnreachable("Timed out")))
    }

    func testHealthTrackerExpiresOldFailureOutsideWindow() {
        var tracker = ServerHealthTracker(failureWindow: 15, tripThreshold: 2)
        let t0 = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(
            tracker.record(.failure(.serverError(503), message: nil), currentState: .online, now: t0),
            .remain
        )
        XCTAssertEqual(
            tracker.record(
                .failure(.serverError(503), message: nil),
                currentState: .online,
                now: t0.addingTimeInterval(20)
            ),
            .remain
        )
    }

    func testHealthTrackerTripsImmediatelyOnNoNetworkAndAuthFailure() {
        var tracker = ServerHealthTracker()
        let now = Date()

        XCTAssertEqual(
            tracker.record(.failure(.noNetwork, message: nil), currentState: .online, now: now),
            .tripDegraded(.noNetwork)
        )
        XCTAssertEqual(
            tracker.record(.failure(.authFailure, message: "Bad credentials"), currentState: .online, now: now),
            .tripDegraded(.authRequired("Bad credentials"))
        )
    }

    func testHealthTrackerIgnoresClientErrorsCancellationsAndManualOffline() {
        var tracker = ServerHealthTracker()
        let now = Date()

        XCTAssertEqual(
            tracker.record(.failure(.clientError, message: "404"), currentState: .online, now: now),
            .remain
        )
        XCTAssertEqual(
            tracker.record(.failure(.cancelled, message: nil), currentState: .online, now: now),
            .remain
        )
        XCTAssertEqual(
            tracker.record(.failure(.noNetwork, message: nil), currentState: .manualOffline, now: now),
            .remain
        )
        XCTAssertEqual(
            tracker.record(.success, currentState: .manualOffline, now: now),
            .remain
        )
    }

    func testHealthTrackerSuccessResetsFailuresAndRecoversDegraded() {
        var tracker = ServerHealthTracker()
        let t0 = Date(timeIntervalSince1970: 1_000)

        _ = tracker.record(.failure(.serverError(502), message: nil), currentState: .online, now: t0)
        XCTAssertEqual(tracker.record(.success, currentState: .online, now: t0.addingTimeInterval(1)), .remain)
        XCTAssertTrue(tracker.recentFailureDates.isEmpty)

        let degraded = ConnectionState.degraded(
            reason: .serverUnreachable(nil),
            nextRetryAt: nil,
            consecutiveFailures: 2
        )
        XCTAssertEqual(tracker.record(.success, currentState: degraded, now: t0.addingTimeInterval(2)), .markOnline)
    }

    func testBackoffDelayScheduleNormalAndLowPower() {
        XCTAssertEqual(ServerHealthTracker.backoffDelay(attempt: 1, isLowPowerMode: false), 2)
        XCTAssertEqual(ServerHealthTracker.backoffDelay(attempt: 2, isLowPowerMode: false), 4)
        XCTAssertEqual(ServerHealthTracker.backoffDelay(attempt: 3, isLowPowerMode: false), 8)
        XCTAssertEqual(ServerHealthTracker.backoffDelay(attempt: 4, isLowPowerMode: false), 15)
        XCTAssertEqual(ServerHealthTracker.backoffDelay(attempt: 5, isLowPowerMode: false), 30)
        XCTAssertEqual(ServerHealthTracker.backoffDelay(attempt: 99, isLowPowerMode: false), 30)

        XCTAssertEqual(ServerHealthTracker.backoffDelay(attempt: 1, isLowPowerMode: true), 5)
        XCTAssertEqual(ServerHealthTracker.backoffDelay(attempt: 4, isLowPowerMode: true), 60)
    }

    func testResolvedAllowInsecureHTTPRespectsProfileAndConfig() {
        let app = AppState()
        app.serverConfig.url = "http://192.168.1.5:4533"
        app.serverConfig.allowInsecureHTTP = true
        XCTAssertTrue(app.resolvedAllowInsecureHTTP)

        app.serverConfig.allowInsecureHTTP = nil
        XCTAssertTrue(app.resolvedAllowInsecureHTTP)

        app.serverConfig.url = "https://music.example.com"
        app.serverConfig.allowInsecureHTTP = nil
        XCTAssertFalse(app.resolvedAllowInsecureHTTP)
    }

    func testDegradedModeSucceedsWithZeroDownloadedTracksAndPreservesNavigation() async {
        defer { CoverArtStore.shared.configure(client: nil, cache: nil) }
        let app = AppState()
        app.serverConfig.url = "https://music.example.com"
        app.serverConfig.username = "tester"
        app.serverConfig.autoReconnectEnabled = false
        let album = SubsonicAlbum(id: "alb-1", title: "Album One")
        app.nav.history = [.album(album)]

        await app.enterDegradedMode(reason: .serverUnreachable("Timeout"))

        XCTAssertTrue(app.isOfflineSession)
        XCTAssertFalse(app.isOnline)
        XCTAssertFalse(app.allowsNetworkRequests)
        XCTAssertTrue(app.circuitGate.isOpen)
        XCTAssertEqual(app.offlineReason, .serverUnreachable("Timeout"))
        XCTAssertEqual(app.nav.history, [.album(album)])
    }

    func testAuthRequiredDisablesAutoReconnect() {
        let app = AppState()
        app.serverConfig.url = "https://music.example.com"
        app.serverConfig.autoReconnectEnabled = true
        app.serverConfig.forceOfflineMode = false

        app.updateConnectionState(.degraded(reason: .serverUnreachable(nil), nextRetryAt: nil, consecutiveFailures: 1))
        XCTAssertTrue(app.canAutoReconnect)

        app.updateConnectionState(.degraded(reason: .authRequired("Wrong password"), nextRetryAt: nil, consecutiveFailures: 1))
        XCTAssertFalse(app.canAutoReconnect)
        XCTAssertTrue(app.isAuthError)
    }

    func testRestoreOfflineLibraryFiltersFavoritesToStarredSongsOnly() async throws {
        let app = AppState()
        let repo = try SwiftDataOfflineRepository.makeInMemory()
        app.offlineRepository = repo

        let starredSong = SubsonicSong(id: "s1", title: "Starred", starred: "2026-01-01T00:00:00Z")
        let normalSong = SubsonicSong(id: "s2", title: "Regular")
        try await repo.saveTrack(starredSong)
        try await repo.saveTrack(normalSong)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("offline-fav-test-\(UUID().uuidString)")
        let cache = CacheManager(rootURL: tempDir)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        app.cache = cache

        let key1 = CacheManager.streamKey(songId: "s1", suffix: "mp3")
        let key2 = CacheManager.streamKey(songId: "s2", suffix: "mp3")
        app.cachedStreamKeys = [
            cache.fileURL(for: .streams, key: key1).lastPathComponent,
            cache.fileURL(for: .streams, key: key2).lastPathComponent
        ]
        app.cachedStreamKeysSeeded = true

        await app.restoreOfflineLibrary()

        XCTAssertEqual(app.library.songs.count, 2)
        XCTAssertEqual(app.library.favoritesSongs.map(\.id), ["s1"])
    }
}
