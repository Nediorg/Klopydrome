import CryptoKit
import Foundation
import NavidromeClient

struct ServerProfile: Codable, Equatable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var url: String
    var username: String
    var authMode: AuthMode
    var allowInsecureHTTP: Bool
    var storageKey: String
    var lastConnectedAt: Date?

    var keychainAccount: String {
        "profile:\(storageKey)"
    }

    init(
        id: UUID = UUID(),
        name: String,
        url: String,
        username: String,
        authMode: AuthMode = .token,
        allowInsecureHTTP: Bool = false,
        storageKey: String? = nil,
        lastConnectedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.username = username
        self.authMode = authMode
        self.allowInsecureHTTP = allowInsecureHTTP
        self.storageKey = storageKey ?? Self.makeStorageKey(url: url, username: username)
        self.lastConnectedAt = lastConnectedAt
    }

    static func makeStorageKey(url: String, username: String) -> String {
        let parsed = URL(string: url)
        let host = parsed?.host?.lowercased() ?? "server"
        let port = parsed?.port.map { ":\($0)" } ?? ""
        let path = parsed?.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        let cleanUser = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let rawCombined = "\(host)\(port)/\(path)/\(cleanUser)"
        let digest = SHA256.hash(data: Data(rawCombined.utf8))
        let hashSuffix = digest.compactMap { String(format: "%02x", $0) }.joined().prefix(8)

        let safeHost = host.replacingOccurrences(of: "[^a-z0-9._-]", with: "-", options: .regularExpression)
        let safeUser = cleanUser.replacingOccurrences(of: "[^a-z0-9._-]", with: "-", options: .regularExpression)
        return "\(safeHost)_\(safeUser)_\(hashSuffix)"
    }
}
