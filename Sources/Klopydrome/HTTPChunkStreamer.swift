import Foundation

enum HTTPChunkStreamer {

    enum Chunk {
        case head(expectedContentLength: Int64)
        case body(Data)
    }

    private static let coordinator = Coordinator()

    static func chunks(from url: URL) -> AsyncThrowingStream<Chunk, Error> {
        coordinator.stream(for: url)
    }

    private final class Coordinator: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        private var session: URLSession!
        private let lock = NSLock()
        private var streams: [Int: AsyncThrowingStream<Chunk, Error>.Continuation] = [:]

        override init() {
            super.init()
            let config = URLSessionConfiguration.default
            config.urlCache = nil
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.timeoutIntervalForRequest = 60
            config.timeoutIntervalForResource = 3600
            config.httpMaximumConnectionsPerHost = 6
            self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        }

        func stream(for url: URL) -> AsyncThrowingStream<Chunk, Error> {
            AsyncThrowingStream { continuation in
                let task = self.session.dataTask(with: url)
                let taskID = task.taskIdentifier

                self.lock.lock()
                self.streams[taskID] = continuation
                self.lock.unlock()

                continuation.onTermination = { [weak self] _ in
                    task.cancel()
                    _ = self?.removeStream(for: taskID)
                }

                task.resume()
            }
        }

        private func removeStream(for taskID: Int) -> AsyncThrowingStream<Chunk, Error>.Continuation? {
            lock.lock()
            defer { lock.unlock() }
            return streams.removeValue(forKey: taskID)
        }

        private func streamContinuation(for taskID: Int) -> AsyncThrowingStream<Chunk, Error>.Continuation? {
            lock.lock()
            defer { lock.unlock() }
            return streams[taskID]
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                        didReceive response: URLResponse,
                        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            guard let continuation = streamContinuation(for: dataTask.taskIdentifier) else {
                completionHandler(.cancel)
                return
            }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                _ = removeStream(for: dataTask.taskIdentifier)
                continuation.finish(throwing: URLError(.badServerResponse))
                completionHandler(.cancel)
                return
            }
            continuation.yield(.head(expectedContentLength: response.expectedContentLength))
            completionHandler(.allow)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            guard let continuation = streamContinuation(for: dataTask.taskIdentifier) else { return }
            continuation.yield(.body(data))
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            guard let continuation = removeStream(for: task.taskIdentifier) else { return }
            if let error {
                continuation.finish(throwing: error)
            } else {
                continuation.finish()
            }
        }
    }
}
