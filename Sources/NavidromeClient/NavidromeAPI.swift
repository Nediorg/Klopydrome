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
    private var _onHealthEvent: (@Sendable (TransportHealthEvent) -> Void)?
    private var _isCircuitOpen: (@Sendable () -> Bool)?

    public var token: String? {
        lock.lock()
        defer { lock.unlock() }
        return _token
    }

    public var onHealthEvent: (@Sendable (TransportHealthEvent) -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _onHealthEvent
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _onHealthEvent = newValue
        }
    }

    public var isCircuitOpen: (@Sendable () -> Bool)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _isCircuitOpen
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _isCircuitOpen = newValue
        }
    }

    public init(baseURL: URL, username: String, password: String, session: URLSession? = nil) {
        self.baseURL = baseURL
        self.username = username
        self.password = password
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 15
            configuration.waitsForConnectivity = false
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.urlCache = nil
            configuration.httpAdditionalHeaders = ["User-Agent": "Klopydrome/1.16.1"]
            self.session = URLSession(configuration: configuration)
        }
    }

    // MARK: - Auth

    public func login() async throws {
        if token != nil { return }
        if isCircuitOpen?() == true { throw NavidromeAPIError.offline }

        var lastTransportError: Error?
        var sawAuthFailure = false

        for endpoint in ["auth/login", "api/authenticate"] {
            switch await attemptLogin(endpoint: endpoint) {
            case .succeeded(let freshToken):
                setToken(freshToken)
                onHealthEvent?(.success)
                return
            case .authRejected:
                sawAuthFailure = true
            case .transportFailed(let error):
                lastTransportError = error
            case .notFound:
                continue
            }
        }

        if let lastTransportError, !sawAuthFailure {
            reportError(lastTransportError)
            throw lastTransportError
        }
        let error = NavidromeAPIError.unauthorized
        reportError(error)
        throw error
    }

    private enum LoginAttemptResult {
        case succeeded(String)
        case authRejected
        case notFound
        case transportFailed(Error)
    }

    private func attemptLogin(endpoint: String) async -> LoginAttemptResult {
        let url = baseURL.appendingPathComponent(endpoint)
        do {
            let body = try JSONEncoder().encode(["username": username, "password": password])
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .transportFailed(NavidromeAPIError.invalidResponse)
            }
            if (200..<300).contains(http.statusCode) {
                if TransportErrorClassifier.isProxyErrorHTML(data, contentType: http.value(forHTTPHeaderField: "Content-Type")) {
                    return .transportFailed(NavidromeAPIError.http(statusCode: 502, message: nil))
                }
                let login = try JSONDecoder().decode(NdLoginResponse.self, from: data)
                return .succeeded(login.token)
            }
            if http.statusCode == 401 || http.statusCode == 403 { return .authRejected }
            if http.statusCode == 404 { return .notFound }
            let message = Self.extractErrorMessage(from: data)
            return .transportFailed(NavidromeAPIError.http(statusCode: http.statusCode, message: message))
        } catch {
            return .transportFailed(error)
        }
    }

    private func setToken(_ newToken: String?) {
        lock.lock()
        _token = newToken
        lock.unlock()
    }

    private func reportError(_ error: Error) {
        let kind = TransportErrorClassifier.classify(error)
        guard kind != .cancelled else { return }
        onHealthEvent?(.failure(kind, message: error.localizedDescription))
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

    public func movePlaylistTrack(playlistId: String, fromIndex: Int, toIndex: Int) async throws {
        let body: [String: Any] = ["insert_before": "\(toIndex)"]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            throw NavidromeAPIError.invalidRequest
        }
        _ = try await send(path: "api/playlist/\(playlistId)/tracks/\(fromIndex)", method: "PUT", body: data)
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
        if isCircuitOpen?() == true { throw NavidromeAPIError.offline }
        try await login()
        guard let token else { throw NavidromeAPIError.unauthorized }
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "X-ND-Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw NavidromeAPIError.invalidResponse
            }
            if http.statusCode == 401 && !isRetry {
                setToken(nil)
                return try await send(path: path, method: method, body: body, isRetry: true)
            }
            if let rotated = http.value(forHTTPHeaderField: "x-nd-authorization"),
               rotated.hasPrefix("Bearer ") {
                setToken(String(rotated.dropFirst("Bearer ".count)))
            }
            guard (200..<300).contains(http.statusCode) else {
                let serverMessage = Self.extractErrorMessage(from: data)
                throw NavidromeAPIError.http(statusCode: http.statusCode, message: serverMessage)
            }
            onHealthEvent?(.success)
            return (data, http)
        } catch {
            reportError(error)
            throw error
        }
    }

    private static func extractErrorMessage(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = json["error"] as? String, !error.isEmpty { return error }
            if let msg = json["message"] as? String, !msg.isEmpty { return msg }
        }
        if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty, text.count < 300, !text.hasPrefix("<") {
            return text
        }
        return nil
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
    case offline
    case http(statusCode: Int, message: String? = nil)

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
        case .offline:
            return NSLocalizedString("Server is currently offline.", comment: "NavidromeAPIError")
        case .http(let code, let message):
            if let message, !message.isEmpty {
                return message
            }
            return String(
                format: NSLocalizedString("Server error (HTTP %lld).", comment: "NavidromeAPIError"),
                code
            )
        }
    }
}