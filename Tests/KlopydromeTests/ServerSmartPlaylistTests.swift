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
            name: "Daily Mix",
            comment: "Recent favourites",
            isPublic: true,
            validUntil: "2026-08-22T00:00:00Z"
        )

        let target = ServerSmartPlaylist(summary: summary)

        XCTAssertEqual(target.id, "smart-1")
        XCTAssertEqual(target.name, "Daily Mix")
        XCTAssertEqual(target.comment, "Recent favourites")
        XCTAssertEqual(target.isPublic, true)
        XCTAssertNil(target.query)
    }

    @MainActor
    func testServerEditorStartsInRulesLoadingState() {
        let editor = SmartPlaylistEditorView(
            playlist: nil,
            server: ServerSmartPlaylist(id: "smart-1", name: "Daily Mix")
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
            name: "Daily Mix", query: query, originalName: "Daily Mix", originalQuery: query
        ))
        XCTAssertTrue(SmartPlaylistEditorView.shouldConfirmDiscard(
            name: "Renamed", query: query, originalName: "Daily Mix", originalQuery: query
        ))
        XCTAssertTrue(SmartPlaylistEditorView.shouldConfirmDiscard(
            name: "Daily Mix", query: changedQuery, originalName: "Daily Mix", originalQuery: query
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
