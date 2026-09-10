import Foundation

/// JWT payload returned by Navidrome's `POST /auth/login` (and the legacy
/// `POST /api/authenticate`). The token authorizes all `/api/*` requests.
private struct NdLoginResponse: Decodable {
    let token: String
    let username: String?
    let isAdmin: Bool?
}

/// Server-side playlist record from `GET /api/playlist/:id`. Only the fields
/// the app needs for smart-playlist rule editing are decoded here; the raw
/// `rules` JSON is carried as a dynamic `NDJSON` so the app can round-trip it
/// through its own editor without loss.
public struct NdPlaylist: Decodable {
    public let id: String
    public let name: String?
    public let comment: String?
    public let ownerName: String?
    public let isPublic: Bool?
    public let sync: Bool?
    public let rules: NDJSON?

    private enum CodingKeys: String, CodingKey {
        case id, name, comment, ownerName, sync, rules
        case isPublic = "public"
    }
}

/// A dynamic JSON value able to hold everything the Navidrome smart-playlist
/// DSL emits: booleans, numbers, strings, nested objects (`all`/`any`/operator
/// wrappers) and the small string arrays used by range operators.
public indirect enum NDJSON: Codable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: NDJSON])
    case array([NDJSON])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) { self = .string(s) }
        else if let d = try? container.decode(Double.self) { self = .number(d) }
        else if let b = try? container.decode(Bool.self) { self = .bool(b) }
        else if let arr = try? container.decode([NDJSON].self) { self = .array(arr) }
        else if let obj = try? container.decode([String: NDJSON].self) { self = .object(obj) }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value") }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .number(let d): try container.encode(d)
        case .bool(let b): try container.encode(b)
        case .object(let o): try container.encode(o)
        case .array(let a): try container.encode(a)
        }
    }
}

/// Navidrome's native JSON REST API (`/api/*`), used only where the Subsonic
/// API has no equivalent — specifically reading/writing the `rules` of
/// server-side smart playlists. The native API is unstable by design, so this
/// client is intentionally thin and best-effort.
///
/// Auth: `POST /auth/login` returns a JWT; it is sent on every `/api/*` request
/// as `X-ND-Authorization: Bearer <token>`. Navidrome rotates the token on each
/// response (returned in the `x-nd-authorization` header), so the client
/// persists every refresh.
public final class NavidromeAPI {
    public let baseURL: URL
    let session: URLSession
    private let username: String
    private let password: String

    /// The currently valid JWT; refreshed on every response via the
    /// `x-nd-authorization` response header.
    public private(set) var token: String?

    public init(baseURL: URL, username: String, password: String, session: URLSession? = nil) {
        self.baseURL = baseURL
        self.username = username
        self.password = password
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 60
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.urlCache = nil
            configuration.httpAdditionalHeaders = ["User-Agent": "Klopydrome/1.16.1"]
            self.session = URLSession(configuration: configuration)
        }
    }

    // MARK: - Auth

    /// Performs `POST /auth/login` (falling back to legacy `/api/authenticate`)
    /// and caches the JWT. No-op when a token is already present.
    public func login() async throws {
        if token != nil { return }
        let endpoints = ["auth/login", "api/authenticate"]
        for endpoint in endpoints {
            guard let url = baseURL.appendingPathComponent(endpoint) as URL? else { continue }
            do {
                let body = try JSONEncoder().encode(["username": username, "password": password])
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = body
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                    let login = try JSONDecoder().decode(NdLoginResponse.self, from: data)
                    token = login.token
                    return
                }
            } catch {
                continue
            }
        }
        throw NavidromeAPIError.unauthorized
    }

    // MARK: - Playlists

    /// Fetches one playlist's server record, including its smart-playlist
    /// `rules` (when it is one). Refreshes the JWT from the response.
    public func getPlaylist(id: String) async throws -> NdPlaylist {
        try await request(path: "api/playlist/\(id)", method: "GET")
    }

    /// Updates a playlist's metadata and/or smart-playlist rules via `PUT`.
    public func updatePlaylist(id: String, name: String? = nil, comment: String? = nil,
                               isPublic: Bool? = nil, rules: NDJSON? = nil) async throws {
        var body: [String: Any] = [:]
        if let name { body["name"] = name }
        if let comment { body["comment"] = comment }
        if let isPublic { body["public"] = isPublic }
        if let rules { body["rules"] = encodeAny(rules) }
        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            throw NavidromeAPIError.invalidRequest
        }
        _ = try await send(path: "api/playlist/\(id)", method: "PUT", body: data)
    }

    /// Creates a playlist (regular or smart) via `POST /api/playlist` and
    /// returns the server's record for the new entity.
    @discardableResult
    public func createPlaylist(name: String, comment: String? = nil,
                               isPublic: Bool? = nil, rules: NDJSON? = nil) async throws -> NdPlaylist {
        var body: [String: Any] = ["name": name]
        if let comment { body["comment"] = comment }
        if let isPublic { body["public"] = isPublic }
        if let rules { body["rules"] = encodeAny(rules) }
        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            throw NavidromeAPIError.invalidRequest
        }
        let (responseData, _) = try await send(path: "api/playlist", method: "POST", body: data)
        return try JSONDecoder().decode(NdPlaylist.self, from: responseData)
    }

    /// Encodes a `NDJSON` value into a JSON-serializable `Any` for `NSJSONSerialization`.
    private func encodeAny(_ json: NDJSON) -> Any {
        switch json {
        case .string(let s): return s
        case .number(let d): return d
        case .bool(let b): return b
        case .object(let o): return o.reduce(into: [String: Any]()) { $0[$1.key] = encodeAny($1.value) }
        case .array(let a): return a.map(encodeAny)
        }
    }

    // MARK: - Shares

    /// Creates a public share (Navidrome's native `POST /api/share`). Unlike the
    /// Subsonic `createShare` endpoint, the native API honours `downloadable`, so
    /// this is the path used for the in-app "Поделиться" action. The share URL is
    /// not returned by the server (its `url` field is `json:"-"`), so callers
    /// build it as `<baseURL>/share/<id>`.
    ///
    /// - Parameters:
    ///   - resourceIds: One or more Navidrome entity ids (song / album / playlist /
    ///     artist). Multiple ids are joined with commas per the model's `resourceIds`
    ///     field.
    ///   - description: Optional human label; falls back to the server-generated
    ///     contents label when empty.
    ///   - expiresAt: Optional expiry; `nil` lets the server apply its default.
    ///   - downloadable: Whether visitors may download the shared items.
    @discardableResult
    public func createShare(resourceIds: [String], description: String? = nil,
                            expiresAt: Date? = nil, downloadable: Bool = false) async throws -> NdShare {
        var body: [String: Any] = ["resourceIds": resourceIds.joined(separator: ",")]
        if let description, !description.isEmpty { body["description"] = description }
        if let expiresAt { body["expiresAt"] = navidromeShareDateFormatter.string(from: expiresAt) }
        body["downloadable"] = downloadable
        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            throw NavidromeAPIError.invalidRequest
        }
        let (responseData, _) = try await send(path: "api/share", method: "POST", body: data)
        return try JSONDecoder().decode(NdShare.self, from: responseData)
    }

    // MARK: - Request plumbing

    private func request<T: Decodable>(path: String, method: String) async throws -> T {
        let (data, _) = try await send(path: path, method: method, body: nil)
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Sends an authenticated request, persisting any JWT rotation from the
    /// response header, and returns the response data.
    private func send(path: String, method: String, body: Data?) async throws -> (Data, HTTPURLResponse) {
        try await login()
        guard let token else { throw NavidromeAPIError.unauthorized }
        guard let url = baseURL.appendingPathComponent(path) as URL? else {
            throw NavidromeAPIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "X-ND-Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NavidromeAPIError.invalidResponse
        }
        // Navidrome rotates the JWT on every response; keep the fresh token.
        if let rotated = http.value(forHTTPHeaderField: "x-nd-authorization"),
           rotated.hasPrefix("Bearer ") {
            self.token = String(rotated.dropFirst("Bearer ".count))
        }
        guard (200..<300).contains(http.statusCode) else {
            throw NavidromeAPIError.http(statusCode: http.statusCode)
        }
        return (data, http)
    }
}

/// Minimal projection of Navidrome's `Share` model. Only `id` is required to
/// build the public share URL; the rest are decoded best-effort and ignored
/// if absent.
public struct NdShare: Decodable {
    public let id: String
    public let description: String?
    public let downloadable: Bool?
    public let resourceType: String?
    public let contents: String?
}

/// File-scope RFC3339 formatter for the native share API's `expiresAt` field.
let navidromeShareDateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()

/// Errors thrown by the Navidrome native-API client.
public enum NavidromeAPIError: LocalizedError {
    case invalidURL
    case invalidRequest
    case invalidResponse
    case unauthorized
    case http(statusCode: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return NSLocalizedString("Некорректный адрес сервера.", comment: "NavidromeAPIError")
        case .invalidRequest: return NSLocalizedString("Не удалось сформировать запрос.", comment: "NavidromeAPIError")
        case .invalidResponse: return NSLocalizedString("Неожиданный ответ сервера.", comment: "NavidromeAPIError")
        case .unauthorized:
            return NSLocalizedString(
                "Не удалось авторизоваться на сервере.",
                comment: "NavidromeAPIError"
            )
        case .http(let code):
            return String(
                format: NSLocalizedString("Ошибка сервера (HTTP %lld).", comment: "NavidromeAPIError"),
                code
            )
        }
    }
}