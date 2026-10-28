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

enum DiscordRPCFrame {
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

    static func isReady(_ payload: Data) -> Bool {
        guard let object = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any] else {
            return false
        }
        return object["evt"] as? String == "READY"
    }

    static func isError(_ payload: Data) -> Bool {
        guard let object = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any] else {
            return false
        }
        return object["evt"] as? String == "ERROR"
    }
}

enum DiscordRPCTransport {
    private struct Frame {
        let opcode: UInt32
        let payload: Data
    }

    enum ConnectionStatus: Equatable {
        case idle
        case connected
        case discordNotRunning
        case invalidApplicationID
        case handshakeFailed
        case activityRejected

        var label: String {
            switch self {
            case .idle: return "Idle"
            case .connected: return "Connected to Discord"
            case .discordNotRunning: return "Discord not running"
            case .invalidApplicationID: return "Invalid Application ID"
            case .handshakeFailed: return "Failed to connect to Discord"
            case .activityRejected: return "Activity rejected"
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
    private static let handshakeTimeout: TimeInterval = 60
    private static let reconnectCooldown: TimeInterval = 30
    private static var descriptor: Int32?
    private static var connectedApplicationID: String?
    private static var lastConnectionFailure: Date?
    private static var connectionGeneration = 0

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
            drainIncomingFrames(from: descriptor)
        }
    }

    static func clear(applicationID: String) {
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
            lastConnectionFailure = nil
        }
    }

    private static func connectIfNeeded(applicationID: String) -> Bool {
        if let descriptor, connectedApplicationID == applicationID, isConnectionUsable(descriptor) {
            return true
        }
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
            if connectionGeneration == generation {
                report(.handshakeFailed)
            }
            return false
        }
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

    private static func isConnectionUsable(_ descriptor: Int32) -> Bool {
        var pfd = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
        guard Darwin.poll(&pfd, 1, 0) >= 0 else { return false }
        let dead = Int16(POLLHUP | POLLERR | POLLNVAL)
        guard pfd.revents & dead == 0 else { return false }
        if pfd.revents & Int16(POLLIN) != 0 {
            var byte: UInt8 = 0
            let read = Darwin.recv(descriptor, &byte, 1, MSG_PEEK)
            if read == 0 { return false }
            if read < 0, errno != EWOULDBLOCK, errno != EAGAIN { return false }
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
        directories.append(NSTemporaryDirectory())
        directories.append("/tmp")

        var seen = Set<String>()
        return directories
            .filter { seen.insert($0).inserted }
            .flatMap { directory in
                (0...9).map { (directory as NSString).appendingPathComponent("discord-ipc-\($0)") }
            }
    }

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
