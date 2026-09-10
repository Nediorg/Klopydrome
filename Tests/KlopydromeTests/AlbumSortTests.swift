import XCTest
@testable import Klopydrome
import NavidromeClient

@MainActor
final class AlbumSortTests: XCTestCase {
    private func album(_ id: String, title: String, year: Int? = nil,
                       playCount: Int? = nil, created: String? = nil) -> SubsonicAlbum {
        SubsonicAlbum(id: id, title: title, playCount: playCount, created: created, year: year)
    }

    func testMissingYearsUseNameAsStableTieBreaker() {
        let albums = [album("z", title: "Zulu"), album("a", title: "Alpha")]

        XCTAssertEqual(sortedAlbums(albums, by: .release, descending: false).map(\.id), ["a", "z"])
    }

    func testMissingPlayCountsUseNameAsStableTieBreaker() {
        let albums = [album("z", title: "Zulu"), album("a", title: "Alpha")]

        XCTAssertEqual(sortedAlbums(albums, by: .playCount, descending: true).map(\.id), ["a", "z"])
    }

    func testMissingCreatedDatesUseNameAsStableTieBreaker() {
        let albums = [album("z", title: "Zulu"), album("a", title: "Alpha")]

        XCTAssertEqual(sortedAlbums(albums, by: .recentlyAdded, descending: false).map(\.id), ["a", "z"])
    }
}
