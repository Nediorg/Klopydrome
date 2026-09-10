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
}