import Foundation

public enum TransportFailureKind: Equatable, Sendable {
    case noNetwork
    case serverUnreachable
    case serverError(Int)
    case authFailure
    case clientError
    case cancelled
}

public enum TransportHealthEvent: Equatable, Sendable {
    case success
    case failure(TransportFailureKind, message: String?)
}

public enum TransportErrorClassifier {
    public static func classify(_ error: Error) -> TransportFailureKind {
        if error is CancellationError {
            return .cancelled
        }
        if let urlError = error as? URLError {
            return classifyURLError(urlError)
        }
        if let subsonicError = error as? SubsonicError {
            return classifySubsonicError(subsonicError)
        }
        if let apiError = error as? NavidromeAPIError {
            return classifyNavidromeAPIError(apiError)
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return classifyURLError(URLError(URLError.Code(rawValue: nsError.code)))
        }
        return .clientError
    }

    public static func isProxyErrorHTML(_ data: Data, contentType: String? = nil) -> Bool {
        if let contentType, contentType.lowercased().contains("text/html") {
            return true
        }
        guard !data.isEmpty else { return false }
        let prefixData = data.prefix(256)
        guard let prefix = String(data: prefixData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() else {
            return false
        }
        return prefix.hasPrefix("<!doctype html") ||
            prefix.hasPrefix("<html") ||
            prefix.hasPrefix("<head") ||
            prefix.hasPrefix("<body")
    }

    private static func classifyURLError(_ error: URLError) -> TransportFailureKind {
        switch error.code {
        case .cancelled:
            return .cancelled
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
            return .noNetwork
        case .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
             .dnsLookupFailed, .secureConnectionFailed, .serverCertificateHasBadDate,
             .serverCertificateUntrusted, .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid, .cannotLoadFromNetwork, .badServerResponse:
            return .serverUnreachable
        default:
            return .clientError
        }
    }

    private static func classifySubsonicError(_ error: SubsonicError) -> TransportFailureKind {
        switch error {
        case .offline:
            return .cancelled
        case .http(let status):
            return classifyHTTPStatus(status)
        case .server(let code, _):
            if [40, 41, 42, 43, 44].contains(code) {
                return .authFailure
            }
            return .clientError
        case .decoding(let description):
            if description.lowercased().contains("<html") || description.lowercased().contains("<!doctype html") {
                return .serverError(502)
            }
            return .clientError
        case .invalidURL, .insecureConnection:
            return .clientError
        }
    }

    private static func classifyNavidromeAPIError(_ error: NavidromeAPIError) -> TransportFailureKind {
        switch error {
        case .offline:
            return .cancelled
        case .unauthorized:
            return .authFailure
        case .http(let statusCode, _):
            return classifyHTTPStatus(statusCode)
        case .invalidResponse:
            return .serverUnreachable
        case .invalidURL, .invalidRequest:
            return .clientError
        }
    }

    public static func classifyHTTPStatus(_ status: Int) -> TransportFailureKind {
        switch status {
        case 401, 403:
            return .authFailure
        case 500...599:
            return .serverError(status)
        default:
            return .clientError
        }
    }
}
