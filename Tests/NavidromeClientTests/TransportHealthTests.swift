import XCTest
@testable import NavidromeClient

final class TransportHealthTests: XCTestCase {

    override func tearDown() {
        super.tearDown()
        HealthMockURLProtocol.requestHandler = nil
    }

    func testClassifierSeparatesOutagesFromClientErrorsAndCancellations() {
        XCTAssertEqual(TransportErrorClassifier.classify(CancellationError()), .cancelled)
        XCTAssertEqual(TransportErrorClassifier.classify(URLError(.cancelled)), .cancelled)
        XCTAssertEqual(TransportErrorClassifier.classify(URLError(.notConnectedToInternet)), .noNetwork)
        XCTAssertEqual(TransportErrorClassifier.classify(URLError(.cannotConnectToHost)), .serverUnreachable)
        XCTAssertEqual(TransportErrorClassifier.classify(URLError(.timedOut)), .serverUnreachable)
        XCTAssertEqual(TransportErrorClassifier.classify(URLError(.dnsLookupFailed)), .serverUnreachable)
        XCTAssertEqual(TransportErrorClassifier.classify(SubsonicError.http(status: 502)), .serverError(502))
        XCTAssertEqual(TransportErrorClassifier.classify(SubsonicError.http(status: 503)), .serverError(503))
        XCTAssertEqual(TransportErrorClassifier.classify(SubsonicError.http(status: 404)), .clientError)
        XCTAssertEqual(TransportErrorClassifier.classify(SubsonicError.http(status: 401)), .authFailure)
        XCTAssertEqual(TransportErrorClassifier.classify(SubsonicError.server(code: 40, message: "Wrong password")), .authFailure)
        XCTAssertEqual(TransportErrorClassifier.classify(SubsonicError.server(code: 44, message: "Invalid API key")), .authFailure)
        XCTAssertEqual(TransportErrorClassifier.classify(SubsonicError.server(code: 70, message: "Not found")), .clientError)
        XCTAssertEqual(TransportErrorClassifier.classify(SubsonicError.offline), .cancelled)
        XCTAssertEqual(TransportErrorClassifier.classify(NavidromeAPIError.unauthorized), .authFailure)
        XCTAssertEqual(TransportErrorClassifier.classify(NavidromeAPIError.http(statusCode: 504)), .serverError(504))
    }

    func testIsProxyErrorHTMLDetectsReverseProxyPages() {
        XCTAssertTrue(TransportErrorClassifier.isProxyErrorHTML(Data("<!DOCTYPE html><html><body>502 Bad Gateway</body></html>".utf8)))
        XCTAssertTrue(TransportErrorClassifier.isProxyErrorHTML(Data("<html>503</html>".utf8)))
        XCTAssertTrue(TransportErrorClassifier.isProxyErrorHTML(Data("oops".utf8), contentType: "text/html; charset=utf-8"))
        XCTAssertFalse(TransportErrorClassifier.isProxyErrorHTML(Data("{\"subsonic-response\":{\"status\":\"ok\"}}".utf8), contentType: "application/json"))
    }

    func testSubsonicClientFailsFastWhenCircuitOpenAndPingProbeBypassesCircuit() async throws {
        let session = makeMockSession()
        let config = SubsonicConfig(
            baseURL: URL(string: "http://mock.subsonic.test")!,
            username: "user",
            password: "secret"
        )
        let client = SubsonicClient(config: config, session: session)

        var networkHits = 0
        var recordedEvents: [TransportHealthEvent] = []
        client.isCircuitOpen = { true }
        client.onHealthEvent = { recordedEvents.append($0) }

        HealthMockURLProtocol.requestHandler = { request in
            networkHits += 1
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let payload = Data("{\"subsonic-response\":{\"status\":\"ok\",\"version\":\"1.16.1\"}}".utf8)
            return (response, payload)
        }

        do {
            try await client.ping()
            XCTFail("Expected SubsonicError.offline when circuit is open")
        } catch let error as SubsonicError {
            XCTAssertEqual(error, .offline)
        }
        XCTAssertEqual(networkHits, 0)
        XCTAssertTrue(recordedEvents.isEmpty)

        try await client.pingProbe(timeout: 2)
        XCTAssertEqual(networkHits, 1)
        XCTAssertEqual(recordedEvents, [.success])
    }

    func testSubsonicClientReportsAuthAndProxyHTMLFailures() async {
        let session = makeMockSession()
        let config = SubsonicConfig(
            baseURL: URL(string: "http://mock.subsonic.test")!,
            username: "user",
            password: "wrong"
        )
        let client = SubsonicClient(config: config, session: session)

        var recordedEvents: [TransportHealthEvent] = []
        client.onHealthEvent = { recordedEvents.append($0) }

        HealthMockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = Data("{\"subsonic-response\":{\"status\":\"failed\",\"version\":\"1.16.1\",\"error\":{\"code\":40,\"message\":\"Bad auth\"}}}".utf8)
            return (response, body)
        }

        _ = try? await client.pingProbe(timeout: 2)
        XCTAssertEqual(recordedEvents.count, 1)
        if case .failure(let kind, _) = recordedEvents.first {
            XCTAssertEqual(kind, .authFailure)
        } else {
            XCTFail("Expected authFailure event")
        }

        recordedEvents.removeAll()
        HealthMockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/html"])!
            return (response, Data("<!DOCTYPE html><html><body>502 Bad Gateway</body></html>".utf8))
        }

        _ = try? await client.pingProbe(timeout: 2)
        XCTAssertEqual(recordedEvents.count, 1)
        if case .failure(let kind, _) = recordedEvents.first {
            XCTAssertEqual(kind, .serverError(502))
        } else {
            XCTFail("Expected serverError(502) event for HTML proxy page")
        }
    }

    func testNavidromeAPILoginDoesNotMask502AsUnauthorizedAndRespectsCircuitBreaker() async {
        let session = makeMockSession()
        let api = NavidromeAPI(
            baseURL: URL(string: "http://mock.navidrome.test")!,
            username: "user",
            password: "secret",
            session: session
        )

        var recordedEvents: [TransportHealthEvent] = []
        api.onHealthEvent = { recordedEvents.append($0) }

        HealthMockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 502, httpVersion: nil, headerFields: nil)!
            return (response, Data("Bad Gateway".utf8))
        }

        do {
            try await api.login()
            XCTFail("Expected HTTP 502 error")
        } catch NavidromeAPIError.http(let status, _) {
            XCTAssertEqual(status, 502)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        if case .failure(let kind, _) = recordedEvents.first {
            XCTAssertEqual(kind, .serverError(502))
        } else {
            XCTFail("Expected serverError(502) health event")
        }

        var hitsAfterOpen = 0
        api.isCircuitOpen = { true }
        HealthMockURLProtocol.requestHandler = { request in
            hitsAfterOpen += 1
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        do {
            try await api.login()
            XCTFail("Expected NavidromeAPIError.offline")
        } catch NavidromeAPIError.offline {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(hitsAfterOpen, 0)
    }

    private func makeMockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HealthMockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

private final class HealthMockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
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
