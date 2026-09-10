import XCTest
@testable import NavidromeClient

final class URLBuildingTests: XCTestCase {

    private func makeClient(base: String = "http://localhost:4533", username: String = "u",
                            password: String = "p") -> SubsonicClient {
        SubsonicClient(config: SubsonicConfig(
            baseURL: URL(string: base)!,
            username: username,
            password: password,
            authMode: .token
        ))
    }

    func testEndpointPath() throws {
        let client = makeClient()
        let url = try client.buildURL(endpoint: "getPlaylists", params: [], json: true)
        XCTAssertTrue(url.path.hasSuffix("/rest/getPlaylists"))
    }

    func testCommonParams() throws {
        let client = makeClient()
        let url = try client.buildURL(endpoint: "ping", params: [], json: true)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertTrue(items.contains { $0.name == "u" && $0.value == "u" })
        XCTAssertTrue(items.contains { $0.name == "v" && $0.value == "1.16.1" })
        XCTAssertTrue(items.contains { $0.name == "c" && $0.value == "Klopydrome" })
        XCTAssertTrue(items.contains { $0.name == "f" && $0.value == "json" })
        XCTAssertTrue(items.contains { $0.name == "t" })
        XCTAssertTrue(items.contains { $0.name == "s" })
    }

    func testBinaryEndpointsSkipJSON() throws {
        let client = makeClient()
        let stream = try XCTUnwrap(client.streamURL(songId: "abc"))
        let cover = try XCTUnwrap(client.coverArtURL(id: "c1", size: 300))
        XCTAssertNil(URLComponents(url: stream, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "f" })
        XCTAssertNil(URLComponents(url: cover, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "f" })
    }

    func testStreamParams() throws {
        let client = makeClient()
        let stream = try XCTUnwrap(client.streamURL(songId: "abc", maxBitRate: 320, format: "mp3"))
        let items = URLComponents(url: stream, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertTrue(items.contains { $0.name == "id" && $0.value == "abc" })
        XCTAssertTrue(items.contains { $0.name == "maxBitRate" && $0.value == "320" })
        XCTAssertTrue(items.contains { $0.name == "format" && $0.value == "mp3" })
        XCTAssertTrue(items.contains { $0.name == "estimateContentLength" && $0.value == "true" })
    }

    /// The original-format download must explicitly request `format=raw`:
    /// Navidrome otherwise applies AutoTranscodeDownload / player transcoding
    /// to format-less download requests, and its transcoded output can drop
    /// every metadata tag (navidrome#5623).
    func testDownloadRawFormatPinned() throws {
        let client = makeClient()
        let url = try XCTUnwrap(client.downloadURL(songId: "abc", maxBitRate: 0, format: "raw"))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertTrue(items.contains { $0.name == "id" && $0.value == "abc" })
        XCTAssertNil(items.first { $0.name == "maxBitRate" })
        XCTAssertTrue(items.contains { $0.name == "format" && $0.value == "raw" })
    }

    func testRepeatedParamsPreserved() throws {
        let client = makeClient()
        var params = [URLQueryItem(name: "songId", value: "a"),
                      URLQueryItem(name: "songId", value: "b")]
        params.append(contentsOf: client.authQueryItemsForTest)
        let url = try client.buildURL(endpoint: "createPlaylist", params: params, json: true)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(items.filter { $0.name == "songId" }.count, 2)
    }

    func testBaseURLWithPathPrefix() throws {
        let client = makeClient(base: "http://example.com/navidrome")
        let url = try client.buildURL(endpoint: "ping", params: [], json: true)
        XCTAssertTrue(url.path.hasPrefix("/navidrome/rest/ping"))
    }
}

extension SubsonicClient {
    var authQueryItemsForTest: [URLQueryItem] { authQueryItems }
}