import XCTest
@testable import Klopydrome
import NavidromeClient

final class ServerProfileTests: XCTestCase {
    func testStorageKeyGenerationIsDeterministic() {
        let key1 = ServerProfile.makeStorageKey(url: "https://music.example.com:4533/nav", username: "alice")
        let key2 = ServerProfile.makeStorageKey(url: "https://music.example.com:4533/nav", username: "alice")
        XCTAssertEqual(key1, key2)
        XCTAssertFalse(key1.isEmpty)
        XCTAssertTrue(key1.contains("music.example.com"))
        XCTAssertTrue(key1.contains("alice"))
    }

    func testStorageKeyDiffersByPortOrUsername() {
        let key1 = ServerProfile.makeStorageKey(url: "https://music.example.com:4533", username: "alice")
        let key2 = ServerProfile.makeStorageKey(url: "https://music.example.com:4534", username: "alice")
        let key3 = ServerProfile.makeStorageKey(url: "https://music.example.com:4533", username: "bob")

        XCTAssertNotEqual(key1, key2)
        XCTAssertNotEqual(key1, key3)
    }

    func testKeychainAccountUsesStorageKey() {
        let profile = ServerProfile(
            name: "Home",
            url: "https://music.home.arpa:4533",
            username: "user"
        )
        XCTAssertEqual(profile.keychainAccount, "profile:\(profile.storageKey)")
    }

    func testProfileCodableRoundTrip() throws {
        let original = ServerProfile(
            name: "Office",
            url: "https://office.example.com",
            username: "worker",
            authMode: .passwordMD5,
            allowInsecureHTTP: true,
            lastConnectedAt: Date(timeIntervalSince1970: 1000000)
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ServerProfile.self, from: data)

        XCTAssertEqual(original.id, decoded.id)
        XCTAssertEqual(original.name, decoded.name)
        XCTAssertEqual(original.url, decoded.url)
        XCTAssertEqual(original.username, decoded.username)
        XCTAssertEqual(original.authMode, decoded.authMode)
        XCTAssertEqual(original.allowInsecureHTTP, decoded.allowInsecureHTTP)
        XCTAssertEqual(original.storageKey, decoded.storageKey)
        XCTAssertEqual(original.keychainAccount, decoded.keychainAccount)
    }
}
