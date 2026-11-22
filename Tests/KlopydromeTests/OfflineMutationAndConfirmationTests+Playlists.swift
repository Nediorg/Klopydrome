import XCTest
@testable import Klopydrome
import NavidromeClient

extension OfflineMutationAndConfirmationTests {
    func testOfflinePlaylistCreateWithPublicFlagPersists() async {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("test_mutations.json")
        let store = OfflineMutationStore(fileURL: fileURL)

        await store.recordPlaylistCreate(
            name: "Public Playlist",
            songIDs: ["s1", "s2"],
            comment: "My comment",
            isPublic: true
        )

        let mutations = await store.currentMutations()
        XCTAssertEqual(mutations.playlists.count, 1)
        XCTAssertEqual(mutations.playlists.first?.playlistName, "Public Playlist")
        XCTAssertEqual(mutations.playlists.first?.isPublic, true)
        XCTAssertEqual(mutations.playlists.first?.comment, "My comment")

        let reloaded = OfflineMutationStore(fileURL: fileURL)
        let reloadedMutations = await reloaded.currentMutations()
        XCTAssertEqual(reloadedMutations.playlists.first?.isPublic, true)
    }

    func testOfflineMutationStorePlaylistRemoveSongs() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("test_mutations.json")
        let store = OfflineMutationStore(fileURL: fileURL)

        await store.recordPlaylistRemove(playlistID: "pl-rem-idx", indices: [1, 3])

        let mutations = await store.currentMutations()
        XCTAssertEqual(mutations.playlists.count, 1)
        XCTAssertEqual(mutations.playlists.first?.type, .removeSongs)
        XCTAssertEqual(mutations.playlists.first?.playlistID, "pl-rem-idx")
        XCTAssertEqual(mutations.playlists.first?.indices, [1, 3])

        let reloaded = OfflineMutationStore(fileURL: fileURL)
        let reloadedMutations = await reloaded.currentMutations()
        XCTAssertEqual(reloadedMutations.playlists.first?.indices, [1, 3])
    }
}
