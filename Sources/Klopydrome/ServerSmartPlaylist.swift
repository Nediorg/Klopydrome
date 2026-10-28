import Foundation
import NavidromeClient

// MARK: - NDJSON ⟷ SmartQuery

extension SmartQuery {
    init?(ndjson: NDJSON) {
        guard let data = try? JSONEncoder().encode(ndjson),
              let query = try? JSONDecoder().decode(SmartQuery.self, from: data) else {
            return nil
        }
        self = query
    }

    var ndjsonValue: NDJSON {
        guard let data = try? JSONEncoder().encode(self) else { return .object([:]) }
        return (try? JSONDecoder().decode(NDJSON.self, from: data)) ?? .object([:])
    }
}

// MARK: - Server-side smart playlist (editor target)

struct ServerSmartPlaylist: Identifiable, Hashable {
    let id: String
    var name: String
    var isPublic: Bool?
    var comment: String?
    var query: SmartQuery?
}

extension ServerSmartPlaylist {
    init(summary: PlaylistSummary) {
        id = summary.id
        name = summary.displayName
        isPublic = summary.isPublic
        comment = summary.comment
        query = nil
    }
}

// MARK: - AppState: server-side smart-playlist CRUD

extension AppState {
    func loadServerRules(id: String) async -> SmartQuery? {
        guard let navidrome,
              let record = try? await navidrome.getPlaylist(id: id),
              let rules = record.rules else { return nil }
        return SmartQuery(ndjson: rules)
    }

    func saveServerRules(id: String, name: String, isPublic: Bool?,
                         comment: String?, query: SmartQuery) async throws {
        guard let navidrome else { throw SmartPlaylistError.notConnected }
        _ = try await navidrome.updatePlaylist(id: id, name: name, comment: comment,
                                               isPublic: isPublic, rules: query.ndjsonValue)
        invalidatePlaylistDetail(for: id)
        await refreshPlaylists()
        if let updated = library.playlists.first(where: { $0.id == id }) {
            await reloadPlaylist(updated)
        }
    }

    @discardableResult
    func createServerPlaylist(name: String, comment: String?,
                              query: SmartQuery) async throws -> PlaylistSummary? {
        guard let navidrome else { throw SmartPlaylistError.notConnected }
        let created = try await navidrome.createPlaylist(name: name, comment: comment,
                                                         rules: query.ndjsonValue)
        await refreshPlaylists()
        let id = created.id
        return library.playlists.first(where: { $0.id == id })
            ?? PlaylistSummary(id: id, name: name, comment: comment)
    }

    func showServerPlaylist(_ summary: PlaylistSummary) {
        nav.selected = .playlists
        nav.selectedPlaylist = summary
    }

    func showPlaylistsGrid() {
        nav.selected = .playlists
        nav.selectedPlaylist = nil
    }
}
