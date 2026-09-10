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
public final class SubsonicClient {
    public let config: SubsonicConfig
    let session: URLSession

    public init(config: SubsonicConfig, session: URLSession? = nil) {
        self.config = config
        let configuration: URLSessionConfiguration = {
            if let session { return session.configuration }
            let c = URLSessionConfiguration.default
            c.timeoutIntervalForRequest = 60
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

    // MARK: - Auth

    var authQueryItems: [URLQueryItem] {
        var items = [URLQueryItem(name: "u", value: config.username)]
        switch config.authMode {
        case .token:
            let salt = Self.randomSalt(length: 16)
            let token = Self.md5Hex("\(config.password)\(salt)")
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

    func requestData(endpoint: String, params: [URLQueryItem] = [], json: Bool = true) async throws -> Data {
        let url = try buildURL(endpoint: endpoint, params: params, json: json)
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse {
            guard (200..<300).contains(http.statusCode) else {
                throw SubsonicError.http(status: http.statusCode)
            }
        }
        return data
    }

    /// Performs a request and decodes the common envelope, validating `status == "ok"`.
    func requestEnvelope(endpoint: String, params: [URLQueryItem] = []) async throws -> SubsonicEnvelope {
        let data = try await requestData(endpoint: endpoint, params: params)
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