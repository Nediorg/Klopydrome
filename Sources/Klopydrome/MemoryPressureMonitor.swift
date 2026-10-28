import Foundation
import os
import NavidromeClient

private let memoryPressureLogger = Logger(subsystem: "Klopydrome", category: "MemoryPressure")

@MainActor
final class MemoryPressureMonitor {
    static let shared = MemoryPressureMonitor()

    private var source: (any DispatchSourceMemoryPressure)?
    private var isStarted = false

    private init() {}

    func start(onPressure: @escaping @MainActor () -> Void) {
        guard !isStarted else { return }
        isStarted = true

        let memorySource = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        memorySource.setEventHandler {
            let event = memorySource.data
            memoryPressureLogger.warning("macOS memory pressure event received: \(String(describing: event))")
            onPressure()
        }
        memorySource.resume()
        self.source = memorySource
    }

    func stop() {
        source?.cancel()
        source = nil
        isStarted = false
    }
}
