import XCTest
import NavidromeClient
@testable import Klopydrome

@MainActor
final class LyricsStoreSWRTests: XCTestCase {
    func testSWRDiskCacheAndRevalidation() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LyricsSWRTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let cache = CacheManager(rootURL: tempDir)
        let store = LyricsStore()

        let line = SyncedLine(start: 1000, value: "First line")
        let word = SyncedWord(text: "First ", start: 1.0)
        let cached = LyricsStore.CachedLyrics(
            syncedLines: [line],
            wordsByLine: [0: [word]],
            plainText: "Hello world"
        )
        let encoded = try JSONEncoder().encode(cached)
        try await cache.write(data: encoded, to: .metadata, key: LyricsStore.cacheKey(for: "song-swr"))

        let song = SubsonicSong(id: "song-swr", title: "SWR Track")
        await store.load(song: song, client: nil, cache: cache)

        XCTAssertEqual(store.loadedForSongID, "song-swr")
        XCTAssertEqual(store.plainText, "Hello world")
        XCTAssertEqual(store.syncedLines.count, 1)
        XCTAssertEqual(store.syncedLines.first?.value, "First line")
        XCTAssertEqual(store.wordsByLine[0]?.first?.text, "First ")
        XCTAssertFalse(store.isLoading)
    }

    func testSWRBackgroundRevalidationUpdatesCacheAndStore() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LyricsRevalTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
            MockLyricsURLProtocol.requestHandler = nil
        }

        let cache = CacheManager(rootURL: tempDir)
        let store = LyricsStore()

        try await seedStaleLyrics(to: cache, songID: "song-reval")
        let client = makeMockLyricsClient(freshLine: "Updated Fresh Line", start: 2000)

        let song = SubsonicSong(id: "song-reval", title: "Reval Track")
        await store.load(song: song, client: client, cache: cache)

        XCTAssertEqual(store.syncedLines.first?.value, "Updated Fresh Line")
        XCTAssertEqual(store.syncedLines.first?.start, 2000)

        let updatedData = await cache.readData(for: .metadata, key: LyricsStore.cacheKey(for: "song-reval"))
        XCTAssertNotNil(updatedData)
        if let updatedData,
           let updatedLyrics = try? JSONDecoder().decode(LyricsStore.CachedLyrics.self, from: updatedData) {
            XCTAssertEqual(updatedLyrics.syncedLines.first?.value, "Updated Fresh Line")
        }
    }

    private func seedStaleLyrics(to cache: CacheManager, songID: String) async throws {
        let staleLine = SyncedLine(start: 1000, value: "Stale Line")
        let staleCached = LyricsStore.CachedLyrics(
            syncedLines: [staleLine],
            wordsByLine: [:],
            plainText: nil
        )
        let staleData = try JSONEncoder().encode(staleCached)
        try await cache.write(data: staleData, to: .metadata, key: LyricsStore.cacheKey(for: songID))
    }

    private func makeMockLyricsClient(freshLine: String, start: Double) -> SubsonicClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockLyricsURLProtocol.self]
        let session = URLSession(configuration: config)
        let subsonicConfig = SubsonicConfig(
            baseURL: URL(string: "http://mock.lyrics.test")!,
            username: "u",
            password: "p"
        )
        let serverResponse = """
        {"subsonic-response":{"status":"ok","version":"1.16.1",
          "lyricsList":{"structuredLyrics":[
            {"synced":true,"line":[{"start":\(start),"value":"\(freshLine)"}]}
          ]}
        }}
        """
        MockLyricsURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(serverResponse.utf8))
        }
        return SubsonicClient(config: subsonicConfig, session: session)
    }
}

private final class MockLyricsURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.requestHandler else { throw URLError(.badURL) }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
