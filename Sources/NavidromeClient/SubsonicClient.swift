import Foundation
import CryptoKit

public enum AuthMode: String, Codable, CaseIterable, Sendable {
    case token
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

public final class SubsonicClient: @unchecked Sendable {
    public let config: SubsonicConfig
    let session: URLSession
    private var sessionSalt: String
    private var sessionToken: String
    private var _supportedExtensions: Set<String> = []
    private var _extensionVersions: [String: Set<Int>] = [:]
    private var _onHealthEvent: (@Sendable (TransportHealthEvent) -> Void)?
    private var _isCircuitOpen: (@Sendable () -> Bool)?
    private let stateLock = NSLock()

    public var onHealthEvent: (@Sendable (TransportHealthEvent) -> Void)? {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _onHealthEvent
        }
        set {
            stateLock.lock()
            defer { stateLock.unlock() }
            _onHealthEvent = newValue
        }
    }

    public var isCircuitOpen: (@Sendable () -> Bool)? {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _isCircuitOpen
        }
        set {
            stateLock.lock()
            defer { stateLock.unlock() }
            _isCircuitOpen = newValue
        }
    }

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

    public func setOpenSubsonicExtensions(_ extensions: [OpenSubsonicExtension]) {
        stateLock.lock()
        defer { stateLock.unlock() }
        self._supportedExtensions = Set(extensions.map(\.name))
        self._extensionVersions = Dictionary(uniqueKeysWithValues: extensions.map { ($0.name, Set($0.versions)) })
    }

    public func supportsExtension(_ name: String, version: Int = 1) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        if version == 1 && _supportedExtensions.contains(name) { return true }
        return _extensionVersions[name]?.contains(version) == true
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
            items.append(URLQueryItem(name: "p", value: "enc:\(Self.hexEncodedUTF8(config.password))"))
        }
        return items
    }

    static func hexEncodedUTF8(_ string: String) -> String {
        string.utf8.map { String(format: "%02x", $0) }.joined()
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

    struct RequestOptions {
        var maxAttempts: Int = 2
        var bypassCircuitBreaker: Bool = false
        var reportSuccess: Bool = true
    }

    private func isRetryable(error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost:
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

    private func reportHealth(_ event: TransportHealthEvent) {
        onHealthEvent?(event)
    }

    private func reportError(_ error: Error) {
        let kind = TransportErrorClassifier.classify(error)
        guard kind != .cancelled else { return }
        reportHealth(.failure(kind, message: error.localizedDescription))
    }

    private func executeRequest(_ request: URLRequest, options: RequestOptions) async throws -> Data {
        if !options.bypassCircuitBreaker, isCircuitOpen?() == true {
            throw SubsonicError.offline
        }
        var lastError: Error?
        for attempt in 1...max(1, options.maxAttempts) {
            do {
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse {
                    guard (200..<300).contains(http.statusCode) else {
                        throw SubsonicError.http(status: http.statusCode)
                    }
                }
                if options.reportSuccess {
                    reportHealth(.success)
                }
                return data
            } catch {
                lastError = error
                if attempt < options.maxAttempts && isRetryable(error: error) {
                    let delay = Double(attempt) * 0.3
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
                reportError(error)
                throw error
            }
        }
        let fallback = lastError ?? SubsonicError.server(code: 0, message: "Request failed")
        reportError(fallback)
        throw fallback
    }

    func requestData(
        endpoint: String,
        params: [URLQueryItem] = [],
        json: Bool = true,
        maxAttempts: Int = 2
    ) async throws -> Data {
        let url = try buildURL(endpoint: endpoint, params: params, json: json)
        let request = URLRequest(url: url)
        return try await executeRequest(request, options: RequestOptions(maxAttempts: maxAttempts))
    }

    func requestEnvelope(
        endpoint: String,
        params: [URLQueryItem] = [],
        maxAttempts: Int = 2,
        timeout: TimeInterval? = nil,
        bypassCircuitBreaker: Bool = false
    ) async throws -> SubsonicEnvelope {
        let url = try buildURL(endpoint: endpoint, params: params, json: true)
        var request = URLRequest(url: url)
        if let timeout {
            request.timeoutInterval = timeout
        }
        let options = RequestOptions(
            maxAttempts: maxAttempts,
            bypassCircuitBreaker: bypassCircuitBreaker,
            reportSuccess: false
        )
        let data = try await executeRequest(request, options: options)
        return try decodeAndReportEnvelope(from: data)
    }

    func requestPostEnvelope(
        endpoint: String,
        params: [URLQueryItem] = [],
        bodyParams: [URLQueryItem] = []
    ) async throws -> SubsonicEnvelope {
        let url = try buildURL(endpoint: endpoint, params: params, json: true)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var comp = URLComponents()
        comp.queryItems = bodyParams
        let bodyString = comp.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        request.httpBody = bodyString?.data(using: .utf8)
        let options = RequestOptions(maxAttempts: 2, reportSuccess: false)
        let data = try await executeRequest(request, options: options)
        return try decodeAndReportEnvelope(from: data)
    }

    private func decodeAndReportEnvelope(from data: Data) throws -> SubsonicEnvelope {
        do {
            let envelope = try decodeEnvelope(from: data)
            reportHealth(.success)
            return envelope
        } catch {
            if TransportErrorClassifier.isProxyErrorHTML(data) {
                reportHealth(.failure(.serverError(502), message: error.localizedDescription))
            } else {
                reportError(error)
            }
            throw error
        }
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