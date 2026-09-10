import Darwin
import Foundation

private struct DiscordRPCCommand: Encodable {
    struct Arguments: Encodable {
        let pid: Int32
        let activity: DiscordRichPresenceActivity?
    }

    let cmd = "SET_ACTIVITY"
    let args: Arguments
    let nonce = UUID().uuidString
}

/// Pure helpers for the Discord RPC IPC framing protocol. Kept separate from
/// the socket plumbing so handshake/response classification is unit-testable
/// without a live Discord client.
enum DiscordRPCFrame {
    /// Decodes the 8-byte frame header: little-endian opcode + payload length.
    static func parseHeader(_ header: Data) -> (opcode: UInt32, length: UInt32)? {
        guard header.count == 8 else { return nil }
        let opcode = header.withUnsafeBytes { raw in
            raw.load(fromByteOffset: 0, as: UInt32.self).littleEndian
        }
        let length = header.withUnsafeBytes { raw in
            raw.load(fromByteOffset: 4, as: UInt32.self).littleEndian
        }
        return (opcode, length)
    }

    /// True for a successful handshake reply (`cmd: DISPATCH, evt: READY`).
    static func isReady(_ payload: Data) -> Bool {
        guard let object = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any] else {
            return false
        }
        return object["evt"] as? String == "READY"
    }

    /// True when the payload reports an RPC error (`evt: ERROR`).
    static func isError(_ payload: Data) -> Bool {
        guard let object = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any] else {
            return false
        }
        return object["evt"] as? String == "ERROR"
    }
}

/// A Rich Presence activity belongs to its open Discord IPC connection.
/// Keep that connection alive while playback continues; closing it immediately
/// removes the activity even after Discord has accepted `SET_ACTIVITY`.
enum DiscordRPCTransport {
    private struct Frame {
        let opcode: UInt32
        let payload: Data
    }

    /// Connection state surfaced in the Settings window, so a silent
    /// "nothing shows up in Discord" becomes a visible diagnosis.
    enum ConnectionStatus: Equatable {
        case idle
        case connected
        case discordNotRunning
        case invalidApplicationID
        case handshakeFailed
        case activityRejected

        var label: String {
            switch self {
            case .idle: return "Не активно"
            case .connected: return "Подключено к Discord"
            case .discordNotRunning: return "Discord не запущен"
            case .invalidApplicationID: return "Discord отклонил Application ID"
            case .handshakeFailed: return "Не удалось подключиться к Discord"
            case .activityRejected: return "Discord отклонил активность"
            }
        }
    }

    private static let queue = DispatchQueue(label: "com.klopydrome.discord-rpc")
    private static let rpcVersion = 1
    private static let frameOpcode: UInt32 = 1
    private static let closeOpcode: UInt32 = 2
    private static let pingOpcode: UInt32 = 3
    private static let pongOpcode: UInt32 = 4
    private static let handshakeOpcode: UInt32 = 0
    private static let maxFrameSize = 256 * 1024
    /// How long to wait for Discord's READY reply. A healthy client answers in
    /// well under a second, but client-id validation against Discord's API can
    /// take several seconds under load — and back-to-back connection attempts
    /// (rapid toggling, repeated tests) throttle it far harder. The previous
    /// 250 ms socket timeout made the handshake fail almost every time.
    private static let handshakeTimeout: TimeInterval = 60
    /// Minimum pause between failed connection attempts, so a broken Discord or
    /// a bad application id can't be hammered by rapid track changes.
    private static let reconnectCooldown: TimeInterval = 30
    private static var descriptor: Int32?
    private static var connectedApplicationID: String?
    private static var lastConnectionFailure: Date?
    /// Bumped synchronously by `clear()` so a handshake blocked in the poll
    /// loop aborts promptly instead of stalling the serial queue until its
    /// deadline. Int reads/writes are atomic, so the check is race-free enough
    /// for a 100 ms-late abort.
    private static var connectionGeneration = 0

    /// Delivers the latest connection status. Called on the transport queue;
    /// consumers must hop to their own actor before touching shared state.
    static var onStatusChange: ((ConnectionStatus) -> Void)?

    static func setActivity(_ activity: DiscordRichPresenceActivity, applicationID: String) {
        queue.async {
            guard connectIfNeeded(applicationID: applicationID),
                  let payload = try? JSONEncoder().encode(
                      DiscordRPCCommand(args: .init(pid: getpid(), activity: activity))
                  ),
                  let descriptor,
                  sendFrame(opcode: frameOpcode, payload: payload, to: descriptor) else {
                closeConnection()
                return
            }
            report(.connected)
            // Best-effort: classify a rejection reply if it is already waiting;
            // never block the queue for it.
            drainIncomingFrames(from: descriptor)
        }
    }

    static func clear(applicationID: String) {
        // Abort any handshake currently blocked in the poll loop so the user's
        // toggle-off takes effect promptly rather than after the 60 s deadline.
        connectionGeneration &+= 1
        queue.async {
            if connectedApplicationID == applicationID,
               let descriptor,
               let payload = try? JSONEncoder().encode(
                   DiscordRPCCommand(args: .init(pid: getpid(), activity: nil))
               ) {
                _ = sendFrame(opcode: frameOpcode, payload: payload, to: descriptor)
            }
            closeConnection()
            report(.idle)
            // A user-initiated reset (toggle, application id change) should be
            // able to reconnect immediately, not wait out a stale cooldown.
            lastConnectionFailure = nil
        }
    }

    // MARK: Connection lifecycle

    private static func connectIfNeeded(applicationID: String) -> Bool {
        if let descriptor, connectedApplicationID == applicationID, isConnectionUsable(descriptor) {
            return true
        }
        // Back off after a failed attempt: rapid track changes would otherwise
        // open a fresh socket (and wait out the handshake deadline) each time.
        if let lastConnectionFailure,
           Date().timeIntervalSince(lastConnectionFailure) < reconnectCooldown {
            return false
        }
        closeConnection()
        guard let newDescriptor = openSocket() else {
            lastConnectionFailure = Date()
            report(.discordNotRunning)
            return false
        }
        guard performHandshake(on: newDescriptor, applicationID: applicationID) else {
            Darwin.close(newDescriptor)
            lastConnectionFailure = Date()
            return false
        }
        lastConnectionFailure = nil
        descriptor = newDescriptor
        connectedApplicationID = applicationID
        return true
    }

    private static func performHandshake(on descriptor: Int32, applicationID: String) -> Bool {
        let generation = connectionGeneration
        guard let handshake = try? JSONSerialization.data(withJSONObject: [
            "v": rpcVersion,
            "client_id": applicationID
        ]),
        sendFrame(opcode: handshakeOpcode, payload: handshake, to: descriptor),
        waitForReadability(on: descriptor, timeout: handshakeTimeout, generation: generation),
        let response = receiveFrame(from: descriptor) else {
            // An aborted wait means `clear()` is tearing the connection down;
            // the follow-up idle status already reports the user's intent.
            if connectionGeneration == generation {
                report(.handshakeFailed)
            }
            return false
        }
        // Discord rejects an unknown application id with a CLOSE frame
        // ({"code":4000,"message":"Invalid Client ID"}) instead of READY. Treating
        // that as success used to leave a dead socket in the "connected" slot.
        if response.opcode == closeOpcode {
            report(.invalidApplicationID)
            return false
        }
        guard response.opcode == frameOpcode, DiscordRPCFrame.isReady(response.payload) else {
            report(.handshakeFailed)
            return false
        }
        return true
    }

    /// Blocks until `descriptor` is readable, `timeout` elapses, or the
    /// connection generation changes (an aborted handshake). Polling in short
    /// slices keeps the check responsive while allowing Discord's READY to
    /// arrive much later than the 250 ms socket read timeout.
    private static func waitForReadability(
        on descriptor: Int32,
        timeout: TimeInterval,
        generation: Int
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if connectionGeneration != generation { return false }
            var pfd = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let result = Darwin.poll(&pfd, 1, 100)
            if result > 0 {
                let dead = Int16(POLLHUP | POLLERR | POLLNVAL)
                return pfd.revents & dead == 0 && pfd.revents & Int16(POLLIN) != 0
            }
            if result == 0 {
                if Date() >= deadline { return false }
                continue
            }
            return false
        }
    }

    /// True when the cached socket still belongs to a live Discord. Polling with
    /// `POLLIN` reports HUP/ERR/NVAL when the peer went away, so a stale
    /// descriptor (Discord restarted, connection closed by the server) is never
    /// reused for `SET_ACTIVITY`.
    private static func isConnectionUsable(_ descriptor: Int32) -> Bool {
        var pfd = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
        guard Darwin.poll(&pfd, 1, 0) >= 0 else { return false }
        let dead = Int16(POLLHUP | POLLERR | POLLNVAL)
        guard pfd.revents & dead == 0 else { return false }
        if pfd.revents & Int16(POLLIN) != 0 {
            // A zero-length recv (EOF) means the peer half-closed the socket.
            var byte: UInt8 = 0
            let read = Darwin.recv(descriptor, &byte, 1, MSG_PEEK)
            if read == 0 { return false }
            if read < 0, errno != EWOULDBLOCK, errno != EAGAIN { return false }
            // Queued frames (PING / CLOSE / SET_ACTIVITY replies) are drained so
            // PINGs get PONGs and a CLOSE is detected instead of left pending.
            drainIncomingFrames(from: descriptor)
            return isConnectionUsable(descriptor)
        }
        return true
    }

    private static func closeConnection() {
        if let descriptor { Darwin.close(descriptor) }
        descriptor = nil
        connectedApplicationID = nil
    }

    // MARK: Activity responses

    private static func drainIncomingFrames(from descriptor: Int32) {
        while socketHasPendingData(descriptor) {
            guard let frame = receiveFrame(from: descriptor) else {
                closeConnection()
                return
            }
            if frame.opcode == closeOpcode {
                closeConnection()
                return
            }
            if frame.opcode == pingOpcode,
               !sendFrame(opcode: pongOpcode, payload: frame.payload, to: descriptor) {
                closeConnection()
                return
            }
            if frame.opcode == frameOpcode, DiscordRPCFrame.isError(frame.payload) {
                closeConnection()
                report(.activityRejected)
                return
            }
        }
    }

    private static func socketHasPendingData(_ descriptor: Int32) -> Bool {
        var socket = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
        return Darwin.poll(&socket, 1, 0) > 0 && socket.revents != 0
    }

    private static func report(_ status: ConnectionStatus) {
        onStatusChange?(status)
    }
}

// MARK: - Socket plumbing

// In an extension so the type-body lint limit measures the connection state
// machine and the low-level socket helpers separately.

extension DiscordRPCTransport {
    private static func openSocket() -> Int32? {
        for path in socketPaths {
            let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            guard descriptor >= 0 else { return nil }
            configureTimeouts(for: descriptor)
            ignoreSigpipe(on: descriptor)
            if connect(descriptor, to: path) == 0 {
                return descriptor
            }
            Darwin.close(descriptor)
        }
        return nil
    }

    private static var socketPaths: [String] {
        let environment = ProcessInfo.processInfo.environment
        var directories = ["XDG_RUNTIME_DIR", "TMPDIR", "TMP", "TEMP"]
            .compactMap { environment[$0] }
            .filter { !$0.isEmpty }
        // GUI apps launched by Finder/Xcode may not inherit TMPDIR. Foundation
        // still resolves the per-user Darwin temp directory where Discord puts
        // its IPC socket, so include it before the generic /tmp fallback.
        directories.append(NSTemporaryDirectory())
        directories.append("/tmp")

        var seen = Set<String>()
        return directories
            .filter { seen.insert($0).inserted }
            .flatMap { directory in
                (0...9).map { (directory as NSString).appendingPathComponent("discord-ipc-\($0)") }
            }
    }

    /// The per-recv read timeout stays as a backstop: the handshake and the
    /// liveness probe gate their reads on `poll`, so a 250 ms limit is only hit
    /// when a frame is expected but never arrives.
    private static func configureTimeouts(for descriptor: Int32) {
        var timeout = timeval(tv_sec: 0, tv_usec: 250_000)
        withUnsafePointer(to: &timeout) {
            _ = setsockopt(
                descriptor,
                SOL_SOCKET,
                SO_RCVTIMEO,
                $0,
                socklen_t(MemoryLayout<timeval>.size)
            )
            _ = setsockopt(
                descriptor,
                SOL_SOCKET,
                SO_SNDTIMEO,
                $0,
                socklen_t(MemoryLayout<timeval>.size)
            )
        }
    }

    /// Without `SO_NOSIGPIPE` a write to a peer-closed socket raises SIGPIPE and
    /// kills the process. Discord restarts independently (and closes idle
    /// connections), so the option must be set or `send` must never see a
    /// dead peer.
    private static func ignoreSigpipe(on descriptor: Int32) {
        var enabled: Int32 = 1
        _ = setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &enabled,
            socklen_t(MemoryLayout<Int32>.size)
        )
    }

    private static func connect(_ descriptor: Int32, to path: String) -> Int32 {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8) + [0]
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { return -1 }
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            pathBytes.withUnsafeBytes { source in
                destination.baseAddress?.copyMemory(from: source.baseAddress!, byteCount: pathBytes.count)
            }
        }
        let length = socklen_t(MemoryLayout<sa_family_t>.size + pathBytes.count)
        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, length)
            }
        }
    }

    private static func sendFrame(opcode: UInt32, payload: Data, to descriptor: Int32) -> Bool {
        var header = opcode.littleEndian
        var length = UInt32(payload.count).littleEndian
        var frame = Data(bytes: &header, count: MemoryLayout<UInt32>.size)
        frame.append(Data(bytes: &length, count: MemoryLayout<UInt32>.size))
        frame.append(payload)
        return sendAll(frame, to: descriptor)
    }

    private static func receiveFrame(from descriptor: Int32) -> Frame? {
        guard let header = receiveExactly(8, from: descriptor) else { return nil }
        guard let parsed = DiscordRPCFrame.parseHeader(header) else { return nil }
        guard parsed.length <= maxFrameSize,
              let payload = receiveExactly(Int(parsed.length), from: descriptor) else {
            return nil
        }
        return Frame(opcode: parsed.opcode, payload: payload)
    }

    private static func sendAll(_ data: Data, to descriptor: Int32) -> Bool {
        data.withUnsafeBytes { rawBuffer in
            guard var pointer = rawBuffer.baseAddress else { return false }
            var remaining = rawBuffer.count
            while remaining > 0 {
                let sent = Darwin.send(descriptor, pointer, remaining, 0)
                if sent <= 0 { return false }
                remaining -= sent
                pointer = pointer.advanced(by: sent)
            }
            return true
        }
    }

    private static func receiveExactly(_ count: Int, from descriptor: Int32) -> Data? {
        var data = Data(count: count)
        let received = data.withUnsafeMutableBytes { rawBuffer -> Int in
            guard var pointer = rawBuffer.baseAddress else { return 0 }
            var remaining = count
            while remaining > 0 {
                let read = Darwin.recv(descriptor, pointer, remaining, 0)
                if read <= 0 { return 0 }
                remaining -= read
                pointer = pointer.advanced(by: read)
            }
            return count
        }
        return received == count ? data : nil
    }
}
