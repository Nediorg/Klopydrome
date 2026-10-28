import Foundation

actor AsyncGate {
    private let capacity: Int
    private var active = 0
    private var waiters: [Waiter] = []

    private final class Waiter {
        var continuation: CheckedContinuation<Bool, Never>?
        var cancelled = false
    }

    init(capacity: Int) { self.capacity = capacity }

    func acquire() async -> Bool {
        if active < capacity {
            active += 1
            return true
        }
        let waiter = Waiter()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiter.continuation = continuation
                if Task.isCancelled {
                    waiter.cancelled = true
                    Task { await self.resume(waiter, acquired: false) }
                } else {
                    waiters.append(waiter)
                }
            }
        } onCancel: {
            Task { await self.cancel(waiter) }
        }
    }

    func execute<T>(_ work: () async -> T) async -> T? {
        guard await acquire() else { return nil }
        defer { release() }
        return await work()
    }

    func release() {
        active -= 1
        while let waiter = waiters.first {
            waiters.removeFirst()
            if waiter.cancelled { continue }
            active += 1
            let cont = waiter.continuation
            waiter.continuation = nil
            cont?.resume(returning: true)
            break
        }
    }

    private func cancel(_ waiter: Waiter) {
        waiter.cancelled = true
        if let idx = waiters.firstIndex(where: { $0 === waiter }) {
            waiters.remove(at: idx)
        }
        let cont = waiter.continuation
        waiter.continuation = nil
        cont?.resume(returning: false)
    }

    private func resume(_ waiter: Waiter, acquired: Bool) {
        let cont = waiter.continuation
        waiter.continuation = nil
        cont?.resume(returning: acquired)
    }
}
