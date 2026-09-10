import XCTest
import Foundation
@testable import Klopydrome

final class TranscodeSeekTests: XCTestCase {
    private func params(of url: URL) -> [String: String] {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.reduce(into: [String: String]()) { result, item in
                result[item.name] = item.value ?? ""
            } ?? [:]
    }

    func testTranscodeURLGetsTimeOffsetPreservingOtherParams() throws {
        let base = try XCTUnwrap(URL(
            string: "http://host/rest/stream?id=abc&maxBitRate=128&format=opus"
        ))
        let url = try XCTUnwrap(Player.transcodedSeekURL(from: base, at: 123.4))
        let params = params(of: url)
        XCTAssertEqual(params["format"], "opus")
        XCTAssertEqual(params["maxBitRate"], "128")
        XCTAssertEqual(params["id"], "abc")
        XCTAssertEqual(params["timeOffset"], "123")
    }

    func testTranscodeURLReplacesExistingTimeOffset() throws {
        let base = try XCTUnwrap(URL(string: "http://host/rest/stream?id=abc&format=opus&timeOffset=5"))
        let url = try XCTUnwrap(Player.transcodedSeekURL(from: base, at: 30))
        let params = params(of: url)
        XCTAssertEqual(params["timeOffset"], "30")
    }

    func testTranscodeURLClampsNegativeTargetToZero() throws {
        let base = try XCTUnwrap(URL(string: "http://host/rest/stream?id=abc&format=opus"))
        let url = try XCTUnwrap(Player.transcodedSeekURL(from: base, at: -5))
        XCTAssertEqual(params(of: url)["timeOffset"], "0")
    }

    func testDetectsRemoteTranscodeStream() throws {
        XCTAssertTrue(Player.isRemoteTranscodeStreamURL(URL(
            string: "http://host/rest/stream?id=abc&format=opus"
        )))
        XCTAssertFalse(Player.isRemoteTranscodeStreamURL(URL(string: "http://host/rest/stream?id=abc")))
        XCTAssertFalse(Player.isRemoteTranscodeStreamURL(nil))
        XCTAssertFalse(Player.isRemoteTranscodeStreamURL(URL(fileURLWithPath: "/tmp/song.opus")))
    }
}
