import Foundation

private struct NdLoginResponse: Decodable {
    let token: String
    let username: String?
    let isAdmin: Bool?
}

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

public final class NavidromeAPI {
    public let baseURL: URL
    let session: URLSession
    private let username: String
    private let password: String

    private let lock = NSLock()
    private var _token: String?

    public var token: String? {
        lock.lock()
        defer { lock.unlock() }
        return _token
    }

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

    public func login() async throws {
        lock.lock()
        if _token != nil {
            lock.unlock()
            return
        }
        lock.unlock()

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
                    lock.lock()
                    _token = login.token
                    lock.unlock()
                    return
                }
            } catch {
                continue
            }
        }
        throw NavidromeAPIError.unauthorized
    }

    // MARK: - Playlists

    public func getPlaylist(id: String) async throws -> NdPlaylist {
        try await request(path: "api/playlist/\(id)", method: "GET")
    }

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

    private func encodeAny(_ json: NDJSON) -> Any {
        switch json {
        case .string(let s): return s
        case .number(let d): return d
        case .bool(let b): return b
        case .object(let o): return o.reduce(into: [String: Any]()) { $0[$1.key] = encodeAny($1.value) }
        case .array(let a): return a.map(encodeAny)
        }
    }

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

    private func send(
        path: String,
        method: String,
        body: Data?,
        isRetry: Bool = false
    ) async throws -> (Data, HTTPURLResponse) {
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
        if http.statusCode == 401 && !isRetry {
            lock.lock()
            self._token = nil
            lock.unlock()
            return try await send(path: path, method: method, body: body, isRetry: true)
        }
        if let rotated = http.value(forHTTPHeaderField: "x-nd-authorization"),
           rotated.hasPrefix("Bearer ") {
            let fresh = String(rotated.dropFirst("Bearer ".count))
            lock.lock()
            self._token = fresh
            lock.unlock()
        }
        guard (200..<300).contains(http.statusCode) else {
            throw NavidromeAPIError.http(statusCode: http.statusCode)
        }
        return (data, http)
    }
}

public struct NdShare: Decodable {
    public let id: String
    public let description: String?
    public let downloadable: Bool?
    public let resourceType: String?
    public let contents: String?
}

let navidromeShareDateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()

public enum NavidromeAPIError: LocalizedError {
    case invalidURL
    case invalidRequest
    case invalidResponse
    case unauthorized
    case http(statusCode: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return NSLocalizedString("Invalid server URL.", comment: "NavidromeAPIError")
        case .invalidRequest: return NSLocalizedString("Couldn't build the request.", comment: "NavidromeAPIError")
        case .invalidResponse: return NSLocalizedString("Unexpected server response.", comment: "NavidromeAPIError")
        case .unauthorized:
            return NSLocalizedString(
                "Couldn't sign in to the server.",
                comment: "NavidromeAPIError"
            )
        case .http(let code):
            return String(
                format: NSLocalizedString("Server error (HTTP %lld).", comment: "NavidromeAPIError"),
                code
            )
        }
    }
}