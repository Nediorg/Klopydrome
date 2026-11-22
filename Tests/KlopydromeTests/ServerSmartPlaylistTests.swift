import Foundation
import XCTest
@testable import Klopydrome
import NavidromeClient

final class ServerSmartPlaylistTests: XCTestCase {
    override func tearDown() {
        SmartPlaylistURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testEditorTargetPreservesServerPlaylistMetadata() {
        let summary = PlaylistSummary(
            id: "smart-1",
            name: "Smart Mix",
            comment: "Recent favourites",
            isPublic: true,
            validUntil: "2026-08-22T00:00:00Z"
        )

        let target = ServerSmartPlaylist(summary: summary)

        XCTAssertEqual(target.id, "smart-1")
        XCTAssertEqual(target.name, "Smart Mix")
        XCTAssertEqual(target.comment, "Recent favourites")
        XCTAssertEqual(target.isPublic, true)
        XCTAssertNil(target.query)
    }

    @MainActor
    func testServerEditorStartsInRulesLoadingState() {
        let editor = SmartPlaylistEditorView(
            playlist: nil,
            server: ServerSmartPlaylist(id: "smart-1", name: "Smart Mix")
        )

        XCTAssertTrue(editor.isLoadingInitialRules)
    }

    @MainActor
    func testDiscardPromptRequiresSemanticChange() throws {
        let json = #"{"all":[{"gt":{"duration":180}}],"sort":"title"}"#
        let query = try JSONDecoder().decode(SmartQuery.self, from: Data(json.utf8))
        var changedQuery = query
        changedQuery.sort = "artist"

        XCTAssertFalse(SmartPlaylistEditorView.shouldConfirmDiscard(
            name: "Smart Mix", query: query, originalName: "Smart Mix", originalQuery: query
        ))
        XCTAssertTrue(SmartPlaylistEditorView.shouldConfirmDiscard(
            name: "Renamed", query: query, originalName: "Smart Mix", originalQuery: query
        ))
        XCTAssertTrue(SmartPlaylistEditorView.shouldConfirmDiscard(
            name: "Smart Mix", query: changedQuery, originalName: "Smart Mix", originalQuery: query
        ))
    }

    @MainActor
    func testEquivalentJSONKeepsExistingRuleTree() throws {
        let json = #"{"all":[{"gt":{"duration":180}}],"sort":"title"}"#
        let query = try JSONDecoder().decode(SmartQuery.self, from: Data(json.utf8))
        let editor = SmartPlaylistEditorView(playlist: nil)
        editor.model = QueryEditorModel(root: QueryNode(query: query))
        editor.limitText = query.limit.map(String.init) ?? ""
        editor.apply(query.sort)
        editor.jsonText = """
        {
          "all": [{"gt": {"duration": 180}}],
          "sort": "title"
        }
        """
        let originalModel = editor.model

        editor.readFromJSONIfValid()

        XCTAssertTrue(editor.model === originalModel)
    }

    @MainActor
    func testMoveRuleIntoNestedGroup() {
        let root = QueryNode(.group(.all))
        let target = QueryNode(.group(.any))
        let source = QueryNode(.rule(.empty))
        root.children = [target, source]

        XCTAssertTrue(QueryTree.move(nodeID: source.id, intoGroup: target.id, at: 0, root: root))
        XCTAssertEqual(root.children.map(\.id), [target.id])
        XCTAssertEqual(target.children.map(\.id), [source.id])
    }

    @MainActor
    func testLoadServerRulesFetchesAndDecodesSavedRules() async throws {
        let baseURL = try XCTUnwrap(URL(string: "https://navidrome.test"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SmartPlaylistURLProtocol.self]
        let api = NavidromeAPI(
            baseURL: baseURL,
            username: "user",
            password: "password",
            session: URLSession(configuration: configuration)
        )
        let app = AppState()
        app.navidrome = api

        SmartPlaylistURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            switch url.path {
            case "/auth/login":
                return Self.response(for: request, body: #"{"token":"test-token"}"#)
            case "/api/playlist/smart-1":
                return Self.response(
                    for: request,
                    body: #"""
                    {
                      "id": "smart-1",
                      "name": "Daily Mix",
                      "rules": {
                        "all": [{"gt": {"duration": 180}}],
                        "sort": "-rating,title",
                        "limit": 42
                      }
                    }
                    """#
                )
            default:
                throw SmartPlaylistURLProtocol.Error.unexpectedRequest(url.path)
            }
        }

        let query = await app.loadServerRules(id: "smart-1")

        XCTAssertEqual(query?.root.children.first?.op, .gt)
        XCTAssertEqual(query?.sort, "-rating,title")
        XCTAssertEqual(query?.limit, 42)
    }

    @MainActor
    func testCachedLibraryRepoUsesLocalSongsWithoutNetwork() async throws {
        let dummyConfig = SubsonicConfig(
            baseURL: URL(string: "http://127.0.0.1:65534")!,
            username: "u",
            password: "p"
        )
        let client = SubsonicClient(config: dummyConfig)
        let local = [
            SubsonicSong(id: "loc-1", title: "Track One", artist: "Artist A", duration: 200),
            SubsonicSong(id: "loc-2", title: "Track Two", artist: "Artist B", duration: 150)
        ]
        let repo = CachedLibraryRepo(
            client: client,
            cache: nil,
            localSongs: { local }
        )
        let songs = try await repo.fetchPool(genre: nil)
        XCTAssertEqual(songs.count, 2)
        XCTAssertEqual(songs.map(\.id), ["loc-1", "loc-2"])
    }

    @MainActor
    func testMigrateLegacyLocalSmartPlaylistsSendsToServerAndCleansUserDefaults() async throws {
        let baseURL = try XCTUnwrap(URL(string: "https://navidrome.test"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SmartPlaylistURLProtocol.self]
        let api = NavidromeAPI(
            baseURL: baseURL,
            username: "user",
            password: "password",
            session: URLSession(configuration: configuration)
        )
        let app = AppState()
        app.navidrome = api

        let legacyQuery = SmartQuery(
            root: QueryExpr(
                group: .any,
                children: [
                    QueryExpr(rule: .contains, field: "artist", value: .string("Artist One")),
                    QueryExpr(rule: .contains, field: "artist", value: .string("Artist Two"))
                ]
            )
        )
        let legacyPlaylist = SmartPlaylist(name: "Migrated Smart Playlist", query: legacyQuery)
        let encoded = try JSONEncoder().encode([legacyPlaylist])
        UserDefaults.standard.set(encoded, forKey: "smartPlaylists")

        var didCreatePlaylist = false
        SmartPlaylistURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            switch url.path {
            case "/auth/login":
                return Self.response(for: request, body: #"{"token":"test-token"}"#)
            case "/api/playlist":
                didCreatePlaylist = true
                return Self.response(
                    for: request,
                    body: #"""
                    {
                      "id": "migrated-1",
                      "name": "Migrated Smart Playlist",
                      "rules": {
                        "any": [{"contains": {"artist": "Artist One"}}, {"contains": {"artist": "Artist Two"}}]
                      }
                    }
                    """#
                )
            default:
                throw SmartPlaylistURLProtocol.Error.unexpectedRequest(url.path)
            }
        }

        await app.migrateLegacyLocalSmartPlaylists()

        XCTAssertTrue(didCreatePlaylist)
        XCTAssertNil(UserDefaults.standard.data(forKey: "smartPlaylists"))
    }

    @MainActor
    func testSmartPlaylistsGuardedAgainstModifications() async {
        let app = AppState()
        let smart = PlaylistSummary(
            id: "smart-p1",
            name: "Smart Mix",
            validUntil: "2026-11-12T00:00:00Z"
        )
        let normal = PlaylistSummary(
            id: "normal-p1",
            name: "Normal Mix"
        )
        app.library.playlists = [smart, normal]

        let task = app.queueOfflineAddToPlaylist(playlistID: "smart-p1", songIDs: ["song-1"])
        XCTAssertNil(task)

        let song = SubsonicSong(id: "song-1", title: "Test", duration: 100)
        await app.addToPlaylist([song], playlistID: "smart-p1")
        await app.removeSongsFromPlaylist(playlistID: "smart-p1", at: [0])
    }

    private static func response(for request: URLRequest, body: String) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data(body.utf8))
    }
}

private final class SmartPlaylistURLProtocol: URLProtocol {
    enum Error: Swift.Error {
        case unexpectedRequest(String)
        case missingHandler
    }

    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "navidrome.test"
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            guard let handler = Self.requestHandler else { throw Error.missingHandler }
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
