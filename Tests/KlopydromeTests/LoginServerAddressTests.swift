import XCTest
@testable import Klopydrome

final class LoginServerAddressTests: XCTestCase {
    func testSchemelessAddressDefaultsToHTTPS() {
        let address = LoginServerAddress(url: "music.example.com:4533/navidrome")

        XCTAssertEqual(address.scheme, .https)
        XCTAssertEqual(address.host, "music.example.com:4533/navidrome")
        XCTAssertEqual(address.url, "https://music.example.com:4533/navidrome")
    }

    func testHTTPAddressSeparatesSchemeAndHost() {
        let address = LoginServerAddress(url: "http://192.168.1.20:4533/music")

        XCTAssertEqual(address.scheme, .http)
        XCTAssertEqual(address.host, "192.168.1.20:4533/music")
        XCTAssertEqual(address.url, "http://192.168.1.20:4533/music")
    }

    func testHTTPSAddressTrimsWhitespaceAndPreservesPath() {
        let address = LoginServerAddress(url: "  HTTPS://music.example.com/navidrome  ")

        XCTAssertEqual(address.scheme, .https)
        XCTAssertEqual(address.host, "music.example.com/navidrome")
        XCTAssertEqual(address.url, "https://music.example.com/navidrome")
    }

    func testServerDraftValidationAndNormalization() {
        var draft = ServerDraft(
            name: "Main",
            urlString: "music.example.com:4533",
            username: "user",
            password: "secret",
            allowSelfSignedCert: true
        )

        XCTAssertTrue(draft.isValid)
        XCTAssertEqual(draft.normalizedURL?.absoluteString, "https://music.example.com:4533")

        draft.password = ""
        XCTAssertFalse(draft.isValid)

        draft.password = "secret"
        draft.username = "   "
        XCTAssertFalse(draft.isValid)

        draft.username = "user"
        draft.urlString = "ftp://files.example.com"
        XCTAssertNil(draft.normalizedURL)
        XCTAssertFalse(draft.isValid)

        draft.urlString = "http://192.168.1.50:4533"
        XCTAssertTrue(draft.isValid)
        XCTAssertEqual(draft.normalizedURL?.absoluteString, "http://192.168.1.50:4533")
    }
}
