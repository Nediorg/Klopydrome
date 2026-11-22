import Foundation
import NavidromeClient

enum OfflineReason: Equatable, Sendable {
    case manual
    case noNetwork
    case serverUnreachable(String?)
    case authRequired(String?)

    var isAuthFailure: Bool {
        if case .authRequired = self { return true }
        return false
    }

    var errorMessage: String? {
        switch self {
        case .manual, .noNetwork:
            return nil
        case .serverUnreachable(let message), .authRequired(let message):
            return message
        }
    }
}

enum ConnectionState: Equatable, Sendable {
    case unconfigured
    case connecting(attempt: Int)
    case online
    case degraded(reason: OfflineReason, nextRetryAt: Date?, consecutiveFailures: Int)
    case manualOffline
    case reconnecting(previousReason: OfflineReason)

    var isOnline: Bool {
        self == .online
    }

    var isOfflineSession: Bool {
        switch self {
        case .degraded, .manualOffline, .reconnecting:
            return true
        case .unconfigured, .connecting, .online:
            return false
        }
    }

    var isManualOffline: Bool {
        self == .manualOffline
    }

    var isConnecting: Bool {
        if case .connecting = self { return true }
        return false
    }

    var isReconnecting: Bool {
        if case .reconnecting = self { return true }
        return false
    }

    var offlineReason: OfflineReason? {
        switch self {
        case .manualOffline:
            return .manual
        case .degraded(let reason, _, _):
            return reason
        case .reconnecting(let previousReason):
            return previousReason
        case .unconfigured, .connecting, .online:
            return nil
        }
    }

    var isAuthError: Bool {
        offlineReason?.isAuthFailure == true
    }
}

final class AtomicCircuitGate: @unchecked Sendable {
    private let lock = NSLock()
    private var _isOpen = false

    var isOpen: Bool {
        lock.withLock { _isOpen }
    }

    func setOpen(_ open: Bool) {
        lock.withLock { _isOpen = open }
    }
}

struct ServerHealthTracker {
    enum Decision: Equatable {
        case remain
        case markOnline
        case tripDegraded(OfflineReason)
    }

    let failureWindow: TimeInterval
    let tripThreshold: Int
    private(set) var recentFailureDates: [Date] = []
    private(set) var consecutiveProbeFailures: Int = 0

    init(failureWindow: TimeInterval = 15, tripThreshold: Int = 2) {
        self.failureWindow = failureWindow
        self.tripThreshold = tripThreshold
    }

    mutating func reset() {
        recentFailureDates.removeAll()
        consecutiveProbeFailures = 0
    }

    mutating func record(
        _ event: TransportHealthEvent,
        currentState: ConnectionState,
        now: Date = Date()
    ) -> Decision {
        switch event {
        case .success:
            reset()
            if case .degraded = currentState {
                return .markOnline
            }
            return .remain

        case .failure(let kind, let message):
            guard currentState != .manualOffline, currentState != .unconfigured else {
                return .remain
            }
            switch kind {
            case .cancelled, .clientError:
                return .remain
            case .noNetwork:
                recentFailureDates.removeAll()
                return .tripDegraded(.noNetwork)
            case .authFailure:
                recentFailureDates.removeAll()
                return .tripDegraded(.authRequired(message))
            case .serverUnreachable, .serverError:
                recentFailureDates.removeAll { now.timeIntervalSince($0) > failureWindow }
                recentFailureDates.append(now)
                if recentFailureDates.count >= tripThreshold {
                    recentFailureDates.removeAll()
                    return .tripDegraded(.serverUnreachable(message))
                }
                return .remain
            }
        }
    }

    mutating func recordProbeFailure(
        kind: TransportFailureKind,
        message: String?
    ) -> OfflineReason {
        consecutiveProbeFailures += 1
        switch kind {
        case .noNetwork:
            return .noNetwork
        case .authFailure:
            return .authRequired(message)
        case .serverUnreachable, .serverError, .clientError, .cancelled:
            return .serverUnreachable(message)
        }
    }

    static func backoffDelay(attempt: Int, isLowPowerMode: Bool = false) -> TimeInterval {
        let schedule: [TimeInterval] = isLowPowerMode
            ? [5, 15, 30, 60]
            : [2, 4, 8, 15, 30]
        let index = min(max(attempt - 1, 0), schedule.count - 1)
        return schedule[index]
    }
}
