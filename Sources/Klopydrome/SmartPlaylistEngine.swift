import Foundation
import NavidromeClient

enum SmartPlaylistError: LocalizedError {
    case notConnected

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return NSLocalizedString(
                "No connection to server.".localized,
                comment: "SmartPlaylistError"
            )
        }
    }
}

protocol SongRepo {
    func fetchPool(genre: String?) async throws -> [SubsonicSong]
}

final class CachedLibraryRepo: SongRepo {
    private let client: SubsonicClient
    private let diskCache: CacheManager?
    private let localSongs: (@MainActor @Sendable () -> [SubsonicSong])?
    private let albumPageSize = 500
    private let genrePageSize = 500
    private let maxSongs = 10_000
    private let cache = NSCache<NSString, NSArray>()
    private let poolMaxAge: TimeInterval = 12 * 60 * 60

    init(
        client: SubsonicClient,
        cache: CacheManager? = nil,
        localSongs: (@MainActor @Sendable () -> [SubsonicSong])? = nil
    ) {
        self.client = client
        self.diskCache = cache
        self.localSongs = localSongs
        self.cache.countLimit = 8
        self.cache.totalCostLimit = 16 << 20
    }

    func fetchPool(genre: String?) async throws -> [SubsonicSong] {
        let key = (genre ?? "all") as NSString
        if let hit = cache.object(forKey: key) as? [SubsonicSong] {
            return hit
        }

        if let getLocal = localSongs {
            let local = await getLocal()
            if !local.isEmpty {
                let filtered: [SubsonicSong]
                if let genre {
                    filtered = local.filter { $0.genre?.localizedCaseInsensitiveContains(genre) == true }
                } else {
                    filtered = local
                }
                cache.setObject(filtered as NSArray, forKey: key, cost: filtered.count * 2560)
                return filtered
            }
        }

        if let persisted = await loadDisk(genre: genre) {
            cache.setObject(persisted as NSArray, forKey: key, cost: persisted.count * 2560)
            return persisted
        }

        let pool: [SubsonicSong]
        if let genre {
            pool = (try? await client.getSongsByGenre(genre: genre, count: genrePageSize, offset: 0)) ?? []
        } else {
            pool = (try? await client.search3(query: "", artistCount: 0, albumCount: 0, songCount: 500).songs) ?? []
        }
        cache.setObject(pool as NSArray, forKey: key, cost: pool.count * 2560)
        await persist(pool: pool, genre: genre)
        return pool
    }

    func clearMemoryCache() {
        cache.removeAllObjects()
    }

    func clearCache() async {
        cache.removeAllObjects()
        await diskCache?.removeFile(for: .metadata, key: Self.diskKey(for: nil))
    }

    private static func diskKey(for genre: String?) -> String {
        "smartpool-\(genre ?? "all")"
    }

    private func loadDisk(genre: String?) async -> [SubsonicSong]? {
        guard let diskCache else { return nil }
        let fileKey = Self.diskKey(for: genre)
        let url = diskCache.fileURL(for: .metadata, key: fileKey)
        guard let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
              Date().timeIntervalSince(modified) < poolMaxAge,
              let data = await diskCache.readData(for: .metadata, key: fileKey),
              let pool = try? JSONDecoder().decode([SubsonicSong].self, from: data) else {
            return nil
        }
        return pool
    }

    private func persist(pool: [SubsonicSong], genre: String?) async {
        guard let diskCache, let data = try? JSONEncoder().encode(pool) else { return }
        _ = try? await diskCache.write(data: data, to: .metadata, key: Self.diskKey(for: genre))
    }
}

@MainActor
final class SmartPlaylistEngine {
    private let repo: any SongRepo

    init(repo: any SongRepo) {
        self.repo = repo
    }

    func preview(_ query: SmartQuery) async throws -> [SubsonicSong] {
        let genre = SmartQueryMath.genreHint(query)
        let pool = try await repo.fetchPool(genre: genre)
        try Task.checkCancellation()
        return try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let matched = pool.filter { query.matches($0) }
            try Task.checkCancellation()
            let sorted = SmartQueryMath.sort(matched, sort: query.sort, order: query.order, shuffle: false)
            return SmartQueryMath.window(sorted, offset: query.offset, limit: query.limit)
        }.value
    }

    func clearMemoryCache() {
        (repo as? CachedLibraryRepo)?.clearMemoryCache()
    }

    func clearCache() async {
        await (repo as? CachedLibraryRepo)?.clearCache()
    }
}

enum SmartQueryMath {

    enum ComparableBox {
        case number(Double)
        case text(String)

        static func compare(_ lhs: ComparableBox?, _ rhs: ComparableBox?) -> Int {
            switch (lhs, rhs) {
            case let (.number(left)?, .number(right)?):
                return left < right ? -1 : (left > right ? 1 : 0)
            case let (.text(left)?, .text(right)?):
                return left.localizedCaseInsensitiveCompare(right).rawValue
            case (.some, .none): return 1
            case (.none, .some): return -1
            case (.none, .none): return 0
            case (.number, .text), (.text, .number):
                return lhs == nil ? -1 : 1
            }
        }
    }

    static func genreHint(_ query: SmartQuery) -> String? {
        var values = Set<String>()
        collectGenreValues(in: query.root, into: &values)
        return values.count == 1 ? values.first : nil
    }

    static func collectGenreValues(in expr: QueryExpr, into values: inout Set<String>) {
        if expr.isGroup {
            for child in expr.children {
                collectGenreValues(in: child, into: &values)
            }
        } else if expr.field == QueryField.genre.dsl, case .string(let v)? = expr.value,
                  !v.trimmingCharacters(in: .whitespaces).isEmpty {
            values.insert(v)
        }
    }

    static func sort(_ songs: [SubsonicSong], sort: String?, order: String? = nil,
                     shuffle: Bool) -> [SubsonicSong] {
        if shuffle || sort?.contains("random") == true {
            return songs.shuffled()
        }
        let globalDescending = order == "desc"
        let entries: [(key: String, descending: Bool)]
        if let sort {
            entries = sort.split(separator: ",").compactMap(SmartQueryMath.sortEntry)
        } else {
            entries = [("title", false)]
        }
        return songs.sorted { lhs, rhs in
            for entry in entries {
                let order = SmartQueryMath.compare(lhs, rhs, by: entry.key)
                if order != 0 {
                    let descending = entry.descending != globalDescending
                    return descending ? order > 0 : order < 0
                }
            }
            return false
        }
    }

    private static func sortEntry(_ part: Substring) -> (String, Bool)? {
        var field = part
        var descending = false
        if field.hasPrefix("-") { descending = true; field = field.dropFirst() }
        if field.hasPrefix("+") { descending = false; field = field.dropFirst() }
        guard !field.isEmpty else { return nil }
        return (String(field), descending)
    }

    static func window(_ songs: [SubsonicSong], offset: Int?, limit: Int?) -> [SubsonicSong] {
        let skip = max(offset ?? 0, 0)
        if let limit, limit > 0 { return Array(songs.dropFirst(skip).prefix(limit)) }
        return skip > 0 ? Array(songs.dropFirst(skip)) : songs
    }

    private static func compare(_ lhs: SubsonicSong, _ rhs: SubsonicSong, by name: String) -> Int {
        let value: (SubsonicSong) -> ComparableBox?
        switch name {
        case "playcount": value = { song in song.playCount.map { ComparableBox.number(Double($0)) } }
        case "rating": value = { song in song.userRating.map { ComparableBox.number(Double($0)) } }
        case "year": value = { song in song.year.map { ComparableBox.number(Double($0)) } }
        case "duration": value = { song in song.duration.map { ComparableBox.number(Double($0)) } }
        case "dateadded": value = { song in song.created.map { ComparableBox.text($0) } }
        case "artist": value = { song in (song.artist ?? "").isEmpty ? nil : ComparableBox.text(song.artist!) }
        case "album": value = { song in song.album.map { ComparableBox.text($0) } }
        default: value = { song in (song.title ?? "").isEmpty ? nil : ComparableBox.text(song.title!) }
        }
        return ComparableBox.compare(value(lhs), value(rhs))
    }
}
