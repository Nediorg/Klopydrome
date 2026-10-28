import XCTest
@testable import NavidromeClient

final class NavidromeAPITests: XCTestCase {

    override func tearDown() {
        super.tearDown()
        MockAPIURLProtocol.requestHandler = nil
    }

    func test401TokenResetAndRelogin() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockAPIURLProtocol.self]
        let session = URLSession(configuration: config)

        let api = NavidromeAPI(
            baseURL: URL(string: "http://mock.navidrome.test")!,
            username: "admin",
            password: "password",
            session: session
        )

        var loginCount = 0
        var playlistRequestCount = 0

        MockAPIURLProtocol.requestHandler = { [weak self] request in
            guard let self, let url = request.url else { throw MockAPIURLProtocol.MockError.badURL }
            if url.path.hasSuffix("/auth/login") {
                return self.handleLoginRequest(url: url, count: &loginCount)
            } else if url.path.contains("/api/playlist/pl-1") {
                let header = request.value(forHTTPHeaderField: "X-ND-Authorization")
                return self.handlePlaylistRequest(url: url, header: header, count: &playlistRequestCount)
            }
            throw MockAPIURLProtocol.MockError.unhandled(url.path)
        }

        let playlist = try await api.getPlaylist(id: "pl-1")
        XCTAssertEqual(playlist.id, "pl-1")
        XCTAssertEqual(playlist.name, "Smart Playlist")
        XCTAssertEqual(loginCount, 2)
        XCTAssertEqual(playlistRequestCount, 2)
        XCTAssertEqual(api.token, "rotated-jwt-token")
    }

    private func handleLoginRequest(url: URL, count: inout Int) -> (HTTPURLResponse, Data) {
        count += 1
        let tokenString = count == 1 ? "stale-jwt-token" : "fresh-jwt-token"
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data("{\"token\":\"\(tokenString)\",\"username\":\"admin\",\"isAdmin\":true}".utf8))
    }

    private func handlePlaylistRequest(
        url: URL,
        header: String?,
        count: inout Int
    ) -> (HTTPURLResponse, Data) {
        count += 1
        if count == 1 {
            XCTAssertEqual(header, "Bearer stale-jwt-token")
            let response = HTTPURLResponse(
                url: url,
                statusCode: 401,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data())
        }
        XCTAssertEqual(header, "Bearer fresh-jwt-token")
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: [
                "Content-Type": "application/json",
                "x-nd-authorization": "Bearer rotated-jwt-token"
            ]
        )!
        return (response, Data("{\"id\":\"pl-1\",\"name\":\"Smart Playlist\"}".utf8))
    }
}

private final class MockAPIURLProtocol: URLProtocol {
    enum MockError: Error {
        case badURL
        case missingHandler
        case unhandled(String)
    }

    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "mock.navidrome.test"
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            guard let handler = Self.requestHandler else { throw MockError.missingHandler }
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
