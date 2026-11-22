import Foundation
import NavidromeClient
import Network
import Observation

@Observable
final class NetworkMonitor: @unchecked Sendable {
    static let shared = NetworkMonitor()

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.klopydrome.network-monitor", qos: .utility)
    private let lock = NSLock()

    @ObservationIgnored private var _hasReceivedInitialPath = false
    @ObservationIgnored private var _isPathSatisfied = true
    @ObservationIgnored private var _isConstrained = false
    @ObservationIgnored private var _isExpensive = false
    @ObservationIgnored private var _lastFingerprint: String?
    @ObservationIgnored private var initialPathWaiters: [CheckedContinuation<Bool, Never>] = []

    var hasReceivedInitialPath: Bool {
        lock.withLock { _hasReceivedInitialPath }
    }

    var isPathSatisfied: Bool {
        get { lock.withLock { _isPathSatisfied } }
        set { lock.withLock { _isPathSatisfied = newValue } }
    }

    var isConstrained: Bool {
        get { lock.withLock { _isConstrained } }
        set { lock.withLock { _isConstrained = newValue } }
    }

    var isExpensive: Bool {
        get { lock.withLock { _isExpensive } }
        set { lock.withLock { _isExpensive = newValue } }
    }

    var isConstrainedOrExpensive: Bool {
        lock.withLock { _isConstrained || _isExpensive }
    }

    var onConnectivityRestored: (@MainActor () -> Void)?
    var onConnectivityLost: (@MainActor () -> Void)?
    var onPathChanged: (@MainActor () -> Void)?

    private enum PathTransition {
        case none
        case restored
        case lost
        case routeChanged
    }

    private init() {
        monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            self?.handlePathUpdate(path)
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    func waitForInitialPath(timeout: TimeInterval = 1.5) async -> Bool {
        if hasReceivedInitialPath {
            return isPathSatisfied
        }
        return await withTaskGroup(of: Bool?.self) { group in
            group.addTask { [weak self] in
                guard let self else { return true }
                return await withCheckedContinuation { continuation in
                    self.lock.withLock {
                        if self._hasReceivedInitialPath {
                            continuation.resume(returning: self._isPathSatisfied)
                        } else {
                            self.initialPathWaiters.append(continuation)
                        }
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(max(0.1, timeout) * 1_000_000_000))
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result ?? isPathSatisfied
        }
    }

    private func handlePathUpdate(_ path: NWPath) {
        let satisfied = path.status == .satisfied
        let constrained = path.isConstrained
        let expensive = path.isExpensive
        let fingerprint = Self.makeFingerprint(path)

        let (transition, waiters): (PathTransition, [CheckedContinuation<Bool, Never>]) = lock.withLock {
            let hadInitial = _hasReceivedInitialPath
            let wasSatisfied = _isPathSatisfied
            let previousFingerprint = _lastFingerprint

            _hasReceivedInitialPath = true
            _isPathSatisfied = satisfied
            _isConstrained = constrained
            _isExpensive = expensive
            _lastFingerprint = fingerprint

            let pendingWaiters = initialPathWaiters
            initialPathWaiters.removeAll()

            if !hadInitial {
                return (satisfied ? .none : .lost, pendingWaiters)
            }
            if satisfied && !wasSatisfied {
                return (.restored, pendingWaiters)
            }
            if !satisfied && wasSatisfied {
                return (.lost, pendingWaiters)
            }
            if satisfied && previousFingerprint != nil && previousFingerprint != fingerprint {
                return (.routeChanged, pendingWaiters)
            }
            return (.none, pendingWaiters)
        }

        for waiter in waiters {
            waiter.resume(returning: satisfied)
        }

        dispatchTransition(transition)
    }

    private func dispatchTransition(_ transition: PathTransition) {
        switch transition {
        case .none:
            return
        case .restored:
            Task { @MainActor [weak self] in
                self?.onConnectivityRestored?()
            }
        case .lost:
            Task { @MainActor [weak self] in
                self?.onConnectivityLost?()
            }
        case .routeChanged:
            Task { @MainActor [weak self] in
                self?.onPathChanged?()
            }
        }
    }

    private static func makeFingerprint(_ path: NWPath) -> String {
        let interfaces = path.availableInterfaces
            .map { "\($0.type):\($0.name)" }
            .sorted()
            .joined(separator: ",")
        return "\(path.status)|\(interfaces)|\(path.isConstrained)|\(path.isExpensive)"
    }
}
