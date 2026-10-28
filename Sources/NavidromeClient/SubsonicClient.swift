import Foundation
import CryptoKit

/// How credentials are sent to the server.
public enum AuthMode: String, Codable, CaseIterable, Sendable {
    /// Recommended by OpenSubsonic: `t` = MD5(password+salt), `s` = salt.
    case token
    /// Legacy: `p` = hex-encoded MD5 of the password.
    case passwordMD5
}

public struct SubsonicConfig: Equatable, Sendable {
    public var baseURL: URL
    public var username: String
    public var password: String
    public var authMode: AuthMode
    public var clientName: String
    public var apiVersion: String

    public init(baseURL: URL, username: String, password: String,
                authMode: AuthMode = .token,
                clientName: String = "Klopydrome",
                apiVersion: String = "1.16.1") {
        self.baseURL = baseURL
        self.username = username
        self.password = password
        self.authMode = authMode
        self.clientName = clientName
        self.apiVersion = apiVersion
    }
}

/// Thread-safe, stateless HTTP client for the Subsonic (Navidrome) API.
public final class SubsonicClient: @unchecked Sendable {
    public let config: SubsonicConfig
    let session: URLSession
    private var sessionSalt: String
    private var sessionToken: String
    private var _supportedExtensions: Set<String> = []
    private let stateLock = NSLock()

    public var supportedExtensions: Set<String> {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _supportedExtensions
    }

    public func setSupportedExtensions(_ extensions: Set<String>) {
        stateLock.lock()
        defer { stateLock.unlock() }
        self._supportedExtensions = extensions
    }

    public init(config: SubsonicConfig, session: URLSession? = nil) {
        self.config = config
        let salt = Self.randomSalt(length: 16)
        self.sessionSalt = salt
        self.sessionToken = Self.md5Hex("\(config.password)\(salt)")

        let configuration: URLSessionConfiguration = {
            if let session { return session.configuration }
            let c = URLSessionConfiguration.default
            c.timeoutIntervalForRequest = 15
            c.timeoutIntervalForResource = 3600
            c.waitsForConnectivity = false
            c.requestCachePolicy = .reloadIgnoringLocalCacheData
            c.urlCache = nil
            c.httpAdditionalHeaders = ["User-Agent": "\(config.clientName)/\(config.apiVersion)"]
            return c
        }()
        if session != nil {
            self.session = session!
        } else {
            self.session = URLSession(configuration: configuration)
        }
    }

    public func rotateSessionCredentials() {
        stateLock.lock()
        defer { stateLock.unlock() }
        let salt = Self.randomSalt(length: 16)
        self.sessionSalt = salt
        self.sessionToken = Self.md5Hex("\(config.password)\(salt)")
    }

    // MARK: - Auth

    var authQueryItems: [URLQueryItem] {
        stateLock.lock()
        let salt = sessionSalt
        let token = sessionToken
        stateLock.unlock()
        var items = [URLQueryItem(name: "u", value: config.username)]
        switch config.authMode {
        case .token:
            items.append(URLQueryItem(name: "t", value: token))
            items.append(URLQueryItem(name: "s", value: salt))
        case .passwordMD5:
            items.append(URLQueryItem(name: "p", value: "enc:\(Self.md5Hex(config.password))"))
        }
        return items
    }

    static func md5Hex(_ string: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func randomSalt(length: Int) -> String {
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<length).map { _ in letters.randomElement()! })
    }

    // MARK: - URL building

    func buildURL(endpoint: String, params: [URLQueryItem] = [], json: Bool = true) throws -> URL {
        var items = params
        items.append(contentsOf: authQueryItems)
        items.append(URLQueryItem(name: "v", value: config.apiVersion))
        items.append(URLQueryItem(name: "c", value: config.clientName))
        if json {
            items.append(URLQueryItem(name: "f", value: "json"))
        }
        let base = config.baseURL
            .appendingPathComponent("rest")
            .appendingPathComponent(endpoint)
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw SubsonicError.invalidURL
        }
        components.queryItems = items
        guard let url = components.url else {
            throw SubsonicError.invalidURL
        }
        return url
    }

    // MARK: - HTTP

    private func isTransient(error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost:
                return true
            default:
                return false
            }
        }
        if case SubsonicError.http(let status) = error {
            return [502, 503, 504].contains(status)
        }
        return false
    }

    func requestData(
        endpoint: String,
        params: [URLQueryItem] = [],
        json: Bool = true,
        maxAttempts: Int = 3
    ) async throws -> Data {
        var lastError: Error?
        for attempt in 1...maxAttempts {
            do {
                let url = try buildURL(endpoint: endpoint, params: params, json: json)
                let (data, response) = try await session.data(from: url)
                if let http = response as? HTTPURLResponse {
                    guard (200..<300).contains(http.statusCode) else {
                        throw SubsonicError.http(status: http.statusCode)
                    }
                }
                return data
            } catch {
                lastError = error
                if attempt < maxAttempts && isTransient(error: error) {
                    let delay = Double(attempt) * 0.3
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
                throw error
            }
        }
        throw lastError ?? SubsonicError.server(code: 0, message: "Request failed")
    }

    func requestPostData(
        endpoint: String,
        params: [URLQueryItem] = [],
        bodyParams: [URLQueryItem] = [],
        json: Bool = true,
        maxAttempts: Int = 3
    ) async throws -> Data {
        let url = try buildURL(endpoint: endpoint, params: params, json: json)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var comp = URLComponents()
        comp.queryItems = bodyParams
        // URLComponents encodes space as %20 but leaves + unescaped. In application/x-www-form-urlencoded,
        // + represents space, so literal + must be encoded as %2B to prevent server corruption.
        let bodyString = comp.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        request.httpBody = bodyString?.data(using: .utf8)

        var lastError: Error?
        for attempt in 1...maxAttempts {
            do {
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse {
                    guard (200..<300).contains(http.statusCode) else {
                        throw SubsonicError.http(status: http.statusCode)
                    }
                }
                return data
            } catch {
                lastError = error
                if attempt < maxAttempts && isTransient(error: error) {
                    let delay = Double(attempt) * 0.3
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
                throw error
            }
        }
        throw lastError ?? SubsonicError.server(code: 0, message: "Request failed")
    }

    /// Performs a request and decodes the common envelope, validating `status == "ok"`.
    func requestEnvelope(endpoint: String, params: [URLQueryItem] = []) async throws -> SubsonicEnvelope {
        let data = try await requestData(endpoint: endpoint, params: params)
        return try decodeEnvelope(from: data)
    }

    /// Performs a POST request and decodes the common envelope, validating `status == "ok"`.
    func requestPostEnvelope(
        endpoint: String,
        params: [URLQueryItem] = [],
        bodyParams: [URLQueryItem] = []
    ) async throws -> SubsonicEnvelope {
        let data = try await requestPostData(endpoint: endpoint, params: params, bodyParams: bodyParams)
        return try decodeEnvelope(from: data)
    }

    private func decodeEnvelope(from data: Data) throws -> SubsonicEnvelope {
        do {
            let response = try JSONDecoder().decode(SubsonicResponse.self, from: data)
            let envelope = response.subsonicResponse
            guard envelope.status == "ok" else {
                if let error = envelope.error {
                    throw SubsonicError.server(code: error.code, message: error.message)
                }
                throw SubsonicError.server(
                    code: 0,
                    message: "Server returned status '\(envelope.status)'."
                )
            }
            return envelope
        } catch let error as SubsonicError {
            throw error
        } catch {
            let detail = SubsonicDecodingContext.describe(error, from: data)
            throw SubsonicError.decoding(description: detail)
        }
    }
}