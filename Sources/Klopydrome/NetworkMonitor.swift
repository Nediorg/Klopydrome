import Foundation
import Network
import Observation

@Observable
final class NetworkMonitor: @unchecked Sendable {
    static let shared = NetworkMonitor()

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.klopydrome.network-monitor", qos: .utility)
    private let lock = NSLock()

    @ObservationIgnored private var _isPathSatisfied: Bool = true
    @ObservationIgnored private var _isConstrained: Bool = false
    @ObservationIgnored private var _isExpensive: Bool = false

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

    private init() {
        monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let satisfied = path.status == .satisfied
            let constrained = path.isConstrained
            let expensive = path.isExpensive

            let shouldNotify: Bool = self.lock.withLock {
                let previouslyUnsatisfied = !self._isPathSatisfied
                self._isPathSatisfied = satisfied
                self._isConstrained = constrained
                self._isExpensive = expensive
                return satisfied && previouslyUnsatisfied
            }

            if shouldNotify {
                Task { @MainActor [weak self] in
                    self?.onConnectivityRestored?()
                }
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
