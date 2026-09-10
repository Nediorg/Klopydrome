import Foundation
import NavidromeClient

// MARK: - NDJSON ⟷ SmartQuery

extension SmartQuery {
    /// Reconstructs a query from the dynamic JSON the Navidrome native API
    /// stores in a playlist's `rules` field. The conversion goes through an
    /// encode/decode round-trip: `NDJSON` mirrors the raw JSON exactly, and
    /// `SmartQuery` decodes the same document (root expression + sort/limit/
    /// limitPercent/offset/refreshDelay/order meta keys).
    init?(ndjson: NDJSON) {
        guard let data = try? JSONEncoder().encode(ndjson),
              let query = try? JSONDecoder().decode(SmartQuery.self, from: data) else {
            return nil
        }
        self = query
    }

    /// The `rules` payload to persist server-side. Round-trips through JSON so
    /// every (even unknown) field the server stores survives a save unchanged.
    var ndjsonValue: NDJSON {
        guard let data = try? JSONEncoder().encode(self) else { return .object([:]) }
        return (try? JSONDecoder().decode(NDJSON.self, from: data)) ?? .object([:])
    }
}

// MARK: - Server-side smart playlist (editor target)

/// A server-side smart playlist being edited: its tracks are computed by the
/// Navidrome server from its stored `rules`, which the app reads/writes through
/// the native API. Unlike `SmartPlaylist` (a local, client-evaluated query),
/// this struct is not persisted by the app — it is loaded on demand when the
/// user opens the rule editor and thrown away on dismiss.
struct ServerSmartPlaylist: Identifiable, Hashable {
    let id: String
    var name: String
    var isPublic: Bool?
    var comment: String?
    /// The playlist's current `rules`, when the server returned any.
    var query: SmartQuery?
}

extension ServerSmartPlaylist {
    /// Creates a rule-editor target from the server's Subsonic playlist summary.
    /// The editor loads the authoritative rules document on presentation.
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
    /// Loads a server-side smart playlist's `rules` document. Returns nil when
    /// the server holds no rules or the native API is unavailable — in the
    /// editor that means starting from a blank query.
    func loadServerRules(id: String) async -> SmartQuery? {
        guard let navidrome,
              let record = try? await navidrome.getPlaylist(id: id),
              let rules = record.rules else { return nil }
        return SmartQuery(ndjson: rules)
    }

    /// Replaces a server playlist's name and rules in one PUT, then refreshes
    /// the library so the sidebar/grid reflect the change immediately.
    func saveServerRules(id: String, name: String, isPublic: Bool?,
                         comment: String?, query: SmartQuery) async throws {
        guard let navidrome else { throw SmartPlaylistError.notConnected }
        _ = try await navidrome.updatePlaylist(id: id, name: name, comment: comment,
                                               isPublic: isPublic, rules: query.ndjsonValue)
        await refreshPlaylists()
    }

    /// Creates a server-side smart playlist from a rules document and returns
    /// its fresh summary so the caller can navigate to it. Nil when the server
    /// didn't return an id for the new record.
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

    /// Opens a playlist in the detail column (used after "Save as" so the new
    /// server-side smart playlist is immediately visible).
    func showServerPlaylist(_ summary: PlaylistSummary) {
        nav.selected = .playlists
        nav.selectedPlaylist = summary
    }

    /// Returns the detail column to the "All Playlists" grid (used after
    /// "Save as" of a local smart playlist, so the new tile is on screen).
    func showPlaylistsGrid() {
        nav.selected = .playlists
        nav.selectedPlaylist = nil
    }
}
