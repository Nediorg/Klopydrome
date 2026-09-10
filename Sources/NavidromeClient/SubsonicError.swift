import Foundation

public enum SubsonicError: Error, LocalizedError, Equatable {
    case invalidURL
    case insecureConnection
    case http(status: Int)
    case server(code: Int, message: String)
    case decoding(description: String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return NSLocalizedString("Invalid server URL.", comment: "SubsonicError")
        case .insecureConnection:
            return NSLocalizedString(
                "The connection is not secure. Add https:// to the server address, or explicitly allow plain HTTP.",
                comment: "SubsonicError"
            )
        case .http(let status):
            return String(
                format: NSLocalizedString("HTTP error %lld.", comment: "SubsonicError"),
                status
            )
        case .server(let code, let message):
            if code == 40 {
                return NSLocalizedString(
                    "Authentication failed. Check your username and password.",
                    comment: "SubsonicError"
                )
            }
            return String(
                format: NSLocalizedString("Subsonic error %1$lld: %2$@", comment: "SubsonicError"),
                code, message
            )
        case .decoding(let description):
            return String(
                format: NSLocalizedString("Could not parse the server response: %@", comment: "SubsonicError"),
                description
            )
        }
    }
}

/// Wraps a decoding failure so callers can still surface meaningful messages.
public enum SubsonicDecodingContext {
    public static func describe(_ error: Error, from data: Data) -> String {
        let detail = decodeDetail(for: error)
        if let dataString = String(data: data, encoding: .utf8), dataString.count < 2000 {
            return "\(detail) — body: \(dataString)"
        }
        return detail
    }

    private static func decodeDetail(for error: Error) -> String {
        switch error {
        case let error as DecodingError:
            return Self.unwrap(error)
        default:
            return error.localizedDescription
        }
    }

    private static func unwrap(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, let context):
            return "Missing key '\(key.stringValue)' at \(Self.path(context))"
        case .typeMismatch(_, let context):
            return "Type mismatch at \(Self.path(context))"
        case .valueNotFound(_, let context):
            return "Missing value at \(Self.path(context))"
        case .dataCorrupted(let context):
            return "Invalid data at \(Self.path(context))"
        @unknown default:
            return error.localizedDescription
        }
    }

    private static func path(_ context: DecodingError.Context) -> String {
        context.codingPath.isEmpty ? "root" : context.codingPath.map { $0.stringValue }.joined(separator: ".")
    }
}