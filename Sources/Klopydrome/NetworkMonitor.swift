import Foundation
import Network
import Observation

/// Monitors network interface connectivity to enable automatic reconnection
/// when network reachability transitions to satisfied.
@Observable
@MainActor
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.klopydrome.network-monitor", qos: .utility)

    var isPathSatisfied: Bool = true
    var isConstrained: Bool = false
    var isExpensive: Bool = false

    /// Closure invoked on MainActor when network connectivity transitions to satisfied.
    var onConnectivityRestored: (@MainActor () -> Void)?

    private init() {
        monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let satisfied = path.status == .satisfied
                let previouslyUnsatisfied = !self.isPathSatisfied
                self.isPathSatisfied = satisfied
                self.isConstrained = path.isConstrained
                self.isExpensive = path.isExpensive

                if satisfied && previouslyUnsatisfied {
                    self.onConnectivityRestored?()
                }
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
