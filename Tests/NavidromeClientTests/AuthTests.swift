import XCTest
import CryptoKit
@testable import NavidromeClient

final class AuthTests: XCTestCase {

    func testTokenAuthSigning() throws {
        let config = SubsonicConfig(
            baseURL: URL(string: "http://localhost:4533")!,
            username: "alice",
            password: "secret",
            authMode: .token
        )
        let client = SubsonicClient(config: config)
        let url = try client.buildURL(endpoint: "ping", params: [], json: true)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        let salt = query.first { $0.name == "s" }!.value!
        let token = query.first { $0.name == "t" }!.value!
        let expected = SubsonicClient.md5Hex("secret\(salt)")
        XCTAssertEqual(token, expected)
    }

    func testLegacyPasswordAuth() throws {
        let config = SubsonicConfig(
            baseURL: URL(string: "http://localhost:4533")!,
            username: "alice",
            password: "secret",
            authMode: .passwordMD5
        )
        let client = SubsonicClient(config: config)
        let url = try client.buildURL(endpoint: "ping", params: [], json: true)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        let p = query.first { $0.name == "p" }!.value!
        XCTAssertEqual(p, "enc:\(SubsonicClient.md5Hex("secret"))")
        XCTAssertNil(query.first { $0.name == "t" })
    }

    func testMd5Vector() {
        XCTAssertEqual(SubsonicClient.md5Hex("abc"), "900150983cd24fb0d6963f7d28e17f72")
    }

    func testSaltUniquenessAndLength() {
        let a = SubsonicClient.randomSalt(length: 16)
        let b = SubsonicClient.randomSalt(length: 16)
        XCTAssertEqual(a.count, 16)
        XCTAssertEqual(b.count, 16)
        XCTAssertNotEqual(a, b)
    }

    func testSessionSaltStability() throws {
        let config = SubsonicConfig(
            baseURL: URL(string: "http://localhost:4533")!,
            username: "alice",
            password: "secret",
            authMode: .token
        )
        let client = SubsonicClient(config: config)
        let url1 = try client.buildURL(endpoint: "ping", params: [], json: true)
        let query1 = URLComponents(url: url1, resolvingAgainstBaseURL: false)!.queryItems!
        let salt1 = query1.first { $0.name == "s" }!.value!
        let token1 = query1.first { $0.name == "t" }!.value!

        let url2 = try client.buildURL(endpoint: "getStarred2", params: [], json: true)
        let query2 = URLComponents(url: url2, resolvingAgainstBaseURL: false)!.queryItems!
        let salt2 = query2.first { $0.name == "s" }!.value!
        let token2 = query2.first { $0.name == "t" }!.value!

        // Session salt and token must stay stable across requests
        XCTAssertEqual(salt1, salt2)
        XCTAssertEqual(token1, token2)

        // Rotation updates both salt and token
        client.rotateSessionCredentials()

        let url3 = try client.buildURL(endpoint: "ping", params: [], json: true)
        let query3 = URLComponents(url: url3, resolvingAgainstBaseURL: false)!.queryItems!
        let salt3 = query3.first { $0.name == "s" }!.value!
        let token3 = query3.first { $0.name == "t" }!.value!

        XCTAssertNotEqual(salt1, salt3)
        XCTAssertNotEqual(token1, token3)
        XCTAssertEqual(token3, SubsonicClient.md5Hex("secret\(salt3)"))
    }

    func testFormPostBodyEncodingPreservesPlusAndDuplicates() throws {
        let bodyParams = [
            URLQueryItem(name: "id", value: "song+1"),
            URLQueryItem(name: "id", value: "song+2"),
            URLQueryItem(name: "name", value: "Rock + Roll")
        ]
        var comp = URLComponents()
        comp.queryItems = bodyParams
        let bodyString = comp.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        XCTAssertEqual(bodyString, "id=song%2B1&id=song%2B2&name=Rock%20%2B%20Roll")
    }
}