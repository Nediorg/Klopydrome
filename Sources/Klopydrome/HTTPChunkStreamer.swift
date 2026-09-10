import Foundation

/// Streams an HTTP response body as `Data` chunks through a
/// `URLSessionDataDelegate`-backed `AsyncThrowingStream`.
///
/// `URLSession.AsyncBytes` yields one `UInt8` per `await`, so consuming a
/// 15 MB track costs ~15M suspensions plus 15M single-byte appends. This
/// streamer yields the raw network chunks (typically 16–64 KB) instead —
/// the same bytes in ~1/1000 of the iterations, with `Content-Length`
/// delivered up front for progress reporting.
enum HTTPChunkStreamer {

    enum Chunk {
        /// Response headers arrived; carries `Content-Length` when known (-1 when chunked).
        case head(expectedContentLength: Int64)
        /// A body chunk as delivered by the URL loading system.
        case body(Data)
    }

    static func chunks(from url: URL) -> AsyncThrowingStream<Chunk, Error> {
        AsyncThrowingStream { continuation in
            let delegate = Delegate(continuation: continuation)
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            let task = session.dataTask(with: url)
            delegate.task = task
            task.resume()
            // Breaking the session↔delegate retain cycle and stopping the
            // transfer when the consumer goes away (task cancellation, early
            // return on a stale download).
            continuation.onTermination = { _ in
                task.cancel()
                session.invalidateAndCancel()
            }
        }
    }

    private final class Delegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        let continuation: AsyncThrowingStream<Chunk, Error>.Continuation
        weak var task: URLSessionDataTask?

        init(continuation: AsyncThrowingStream<Chunk, Error>.Continuation) {
            self.continuation = continuation
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                        didReceive response: URLResponse,
                        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                continuation.finish(throwing: URLError(.badServerResponse))
                completionHandler(.cancel)
                return
            }
            continuation.yield(.head(expectedContentLength: response.expectedContentLength))
            completionHandler(.allow)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            continuation.yield(.body(data))
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let error {
                continuation.finish(throwing: error)
            } else {
                continuation.finish()
            }
        }
    }
}
