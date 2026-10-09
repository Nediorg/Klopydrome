import XCTest
@testable import Klopydrome
import NavidromeClient

final class PlaylistDuplicateTests: XCTestCase {
    private func song(_ id: String, title: String) -> SubsonicSong {
        SubsonicSong(id: id, title: title)
    }

    func testNoDuplicatesReturnsAddImmediately() {
        let targets = [song("s1", title: "Song 1"), song("s2", title: "Song 2")]
        let existing = [song("s3", title: "Song 3")]

        let result = PlaylistDuplicateResolver.resolve(
            targets: targets,
            existingSongs: existing,
            action: .ask
        )

        XCTAssertEqual(result, .add(songs: targets))
    }

    func testEmptyTargetsReturnsNothingToAdd() {
        let targets: [SubsonicSong] = []
        let existing = [song("s1", title: "Song 1")]

        let result = PlaylistDuplicateResolver.resolve(
            targets: targets,
            existingSongs: existing,
            action: .ask
        )

        XCTAssertEqual(result, .nothingToAdd)
    }

    func testActionAllowReturnsAllTargetsEvenWithDuplicates() {
        let song1 = song("s1", title: "Song 1")
        let song2 = song("s2", title: "Song 2")
        let targets = [song1, song2]
        let existing = [song1]

        let result = PlaylistDuplicateResolver.resolve(
            targets: targets,
            existingSongs: existing,
            action: .allow
        )

        XCTAssertEqual(result, .add(songs: targets))
    }

    func testActionSkipFiltersOutDuplicates() {
        let song1 = song("s1", title: "Song 1")
        let song2 = song("s2", title: "Song 2")
        let song3 = song("s3", title: "Song 3")
        let targets = [song1, song2, song3]
        let existing = [song1, song3]

        let result = PlaylistDuplicateResolver.resolve(
            targets: targets,
            existingSongs: existing,
            action: .skip
        )

        XCTAssertEqual(result, .add(songs: [song2]))
    }

    func testActionSkipWithAllDuplicatesReturnsNothingToAdd() {
        let song1 = song("s1", title: "Song 1")
        let targets = [song1]
        let existing = [song1]

        let result = PlaylistDuplicateResolver.resolve(
            targets: targets,
            existingSongs: existing,
            action: .skip
        )

        XCTAssertEqual(result, .nothingToAdd)
    }

    func testActionAskWithSingleDuplicateReturnsNeedsUserPrompt() {
        let song1 = song("s1", title: "Song 1")
        let targets = [song1]
        let existing = [song1]

        let result = PlaylistDuplicateResolver.resolve(
            targets: targets,
            existingSongs: existing,
            action: .ask
        )

        XCTAssertEqual(result, .needsUserPrompt(duplicates: [song1], allTargets: [song1]))
    }

    func testActionAskWithPartialDuplicatesReturnsNeedsUserPrompt() {
        let song1 = song("s1", title: "Song 1")
        let song2 = song("s2", title: "Song 2")
        let targets = [song1, song2]
        let existing = [song1]

        let result = PlaylistDuplicateResolver.resolve(
            targets: targets,
            existingSongs: existing,
            action: .ask
        )

        XCTAssertEqual(result, .needsUserPrompt(duplicates: [song1], allTargets: targets))
    }
}
