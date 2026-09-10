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
}
