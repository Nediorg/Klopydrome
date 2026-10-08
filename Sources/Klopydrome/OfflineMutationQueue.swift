import Foundation
import NavidromeClient

struct QueuedStarAction: Codable, Equatable, Sendable {
    let id: String
    let kind: StarKind
    let isStarred: Bool
    let timestamp: Date
}

struct QueuedRatingAction: Codable, Equatable, Sendable {
    let songID: String
    let rating: Int
    let timestamp: Date
}

struct OfflineMutations: Codable, Equatable, Sendable {
    var stars: [String: QueuedStarAction] = [:]
    var ratings: [String: QueuedRatingAction] = [:]
}

actor OfflineMutationStore {
    private let fileURL: URL
    private var mutations: OfflineMutations

    init(fileURL: URL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(OfflineMutations.self, from: data) {
            self.mutations = decoded
        } else {
            self.mutations = OfflineMutations()
        }
    }

    init(serverHost: String) {
        let root = CacheManager.root(forServer: serverHost)
        let metadataDir = root.appendingPathComponent("metadata", isDirectory: true)
        try? FileManager.default.createDirectory(at: metadataDir, withIntermediateDirectories: true)
        let url = metadataDir.appendingPathComponent("offline_mutations.json")
        self.fileURL = url
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(OfflineMutations.self, from: data) {
            self.mutations = decoded
        } else {
            self.mutations = OfflineMutations()
        }
    }

    func currentMutations() -> OfflineMutations {
        mutations
    }

    func recordStar(id: String, kind: StarKind, isStarred: Bool) {
        mutations.stars[id] = QueuedStarAction(
            id: id,
            kind: kind,
            isStarred: isStarred,
            timestamp: Date()
        )
        persist()
    }

    func recordRating(songID: String, rating: Int) {
        mutations.ratings[songID] = QueuedRatingAction(
            songID: songID,
            rating: rating,
            timestamp: Date()
        )
        persist()
    }

    func removeStars(ids: Set<String>) {
        for id in ids {
            mutations.stars.removeValue(forKey: id)
        }
        persist()
    }

    func removeRatings(ids: Set<String>) {
        for id in ids {
            mutations.ratings.removeValue(forKey: id)
        }
        persist()
    }

    func clear() {
        mutations = OfflineMutations()
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func persist() {
        if mutations.stars.isEmpty && mutations.ratings.isEmpty {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(mutations) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
