// Local IPC between an app and its command-line companion. macOS: CFMessagePort, from lowkey's
// `lowkeyctl` (no XPC service, no helper, no network socket). Linux: a Unix domain stream socket
// with the same request/reply semantics. The payload format belongs to the app.
#if canImport(Darwin)
import CoreFoundation
import Foundation

/// A named local port that answers each request synchronously on its own serial queue.
public final class MessagePortServer {
    public typealias Handler = (_ messageID: Int32, _ payload: Data) -> Data

    private final class Box {
        let handler: Handler
        init(_ handler: @escaping Handler) { self.handler = handler }
    }

    private let port: CFMessagePort
    public let name: String

    /// `name` must be unique per process: use `MessagePortServer.name(prefix:pid:)`.
    /// Returns nil when the name is taken.
    public init?(name: String, queueLabel: String = "io.bobuk.message-port", handler: @escaping Handler) {
        let box = Unmanaged.passRetained(Box(handler))
        var context = CFMessagePortContext(
            version: 0, info: box.toOpaque(),
            retain: { pointer in
                guard let pointer = pointer else { return nil }
                _ = Unmanaged<Box>.fromOpaque(pointer).retain()
                return UnsafeRawPointer(pointer)
            },
            release: { pointer in
                guard let pointer = pointer else { return }
                Unmanaged<Box>.fromOpaque(pointer).release()
            },
            copyDescription: nil)
        let callback: CFMessagePortCallBack = { _, messageID, data, info in
            guard let info = info else { return nil }
            let box = Unmanaged<Box>.fromOpaque(info).takeUnretainedValue()
            let reply = box.handler(messageID, (data as Data?) ?? Data())
            return .passRetained(reply as CFData)
        }
        let createdPort = CFMessagePortCreateLocal(nil, name as CFString, callback, &context, nil)
        box.release() // The port retained the box through the context.
        guard let port = createdPort else { return nil }
        self.port = port
        self.name = name
        CFMessagePortSetDispatchQueue(port, DispatchQueue(label: queueLabel))
    }

    deinit { CFMessagePortInvalidate(port) }

    /// A versioned, per-process name such as `io.bobuk.lowkey.control.v1.4242`.
    public static func name(prefix: String, version: Int = 1, pid: Int32 = getpid()) -> String {
        "\(prefix).v\(version).\(pid)"
    }

    /// Runs `work` on the main queue and waits for it at most until `deadline`. CFMessagePort needs
    /// a synchronous reply; only the port's queue waits, the main queue stays free.
    public static func replyFromMainQueue(deadline: DispatchTime, fallback: Data,
                                          _ work: @escaping (@escaping (Data) -> Void) -> Void) -> Data {
        final class Result {
            private let lock = NSLock()
            private var data: Data?
            private var delivered = false

            /// The first delivery wins; only it signals the waiter.
            func deliver(_ data: Data) -> Bool {
                lock.lock()
                defer { lock.unlock() }
                guard !delivered else { return false }
                delivered = true
                self.data = data
                return true
            }

            func take() -> Data? {
                lock.lock()
                defer { lock.unlock() }
                return data
            }
        }
        let result = Result()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            if DispatchTime.now() < deadline {
                work { data in
                    if result.deliver(data) { done.signal() }
                }
            } else {
                done.signal()
            }
        }
        return done.wait(timeout: deadline) == .success ? (result.take() ?? fallback) : fallback
    }
}

public enum MessagePortClient {
    public enum Failure: Error, Equatable {
        case notListening
        case sendFailed(Int32)
    }

    /// True when a server listens under `name`.
    public static func isListening(_ name: String) -> Bool {
        CFMessagePortCreateRemote(nil, name as CFString) != nil
    }

    /// Waits up to `timeout` for a server to appear (an app that is still starting). Stops early
    /// when `keepWaiting` turns false, for example because the launched app has quit.
    public static func waitForServer(_ name: String, timeout: TimeInterval,
                                     keepWaiting: @escaping () -> Bool = { true },
                                     completion: @escaping (Bool) -> Void) {
        let deadline = Date().addingTimeInterval(timeout)
        func tick() {
            if isListening(name) { completion(true); return }
            guard Date() < deadline, keepWaiting() else { completion(isListening(name)); return }
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(50)) { tick() }
        }
        tick()
    }

    /// Sends one request and returns the reply. Never retried: a timed-out command may already have
    /// run. `sendTimeout` bounds handing the request to a busy port; `timeout` waits for the reply.
    public static func send(_ payload: Data, to name: String, messageID: Int32 = 1,
                            sendTimeout: TimeInterval? = nil, timeout: TimeInterval) -> Result<Data, Failure> {
        guard let port = CFMessagePortCreateRemote(nil, name as CFString) else { return .failure(.notListening) }
        var response: Unmanaged<CFData>?
        let status = CFMessagePortSendRequest(port, messageID, payload as CFData, sendTimeout ?? timeout, timeout,
                                              CFRunLoopMode.defaultMode.rawValue, &response)
        guard status == kCFMessagePortSuccess, let bytes = response?.takeRetainedValue() else {
            return .failure(.sendFailed(status))
        }
        return .success(bytes as Data)
    }
}
#else
import Foundation

/// Linux backend of `MessagePortServer`: a Unix domain stream socket under the temporary
/// directory, one request at a time on a serial queue, like the CFMessagePort original.
public final class MessagePortServer {
    public typealias Handler = (_ messageID: Int32, _ payload: Data) -> Data

    private let socketPath: String
    private let handler: Handler
    private let queue = DispatchQueue(label: "io.bobuk.message-port")
    private var listenFD: Int32 = -1
    private var source: DispatchSourceRead?

    public let name: String

    /// `name` must be unique per process: use `MessagePortServer.name(prefix:pid:)`.
    /// Returns nil when the name is taken.
    public init?(name: String, queueLabel: String = "io.bobuk.message-port", handler: @escaping Handler) {
        self.name = name
        self.handler = handler
        socketPath = MessagePortSocket.path(for: name)
        unlink(socketPath)
        let fd = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
        guard fd >= 0 else { return nil }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let utf8 = Array(socketPath.utf8)
        guard utf8.count < MemoryLayout.size(ofValue: address.sun_path) else { close(fd); return nil }
        withUnsafeMutablePointer(to: &address.sun_path) { path in
            utf8.withUnsafeBytes { bytes in
                memcpy(path, bytes.baseAddress!, utf8.count)
            }
        }
        let bindResult = withUnsafePointer(to: &address) { addressPointer in
            addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0, listen(fd, 16) == 0 else { close(fd); return nil }
        // Non-blocking: the read-source handler accepts everything pending and must never wait.
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        listenFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptPending() }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    deinit {
        source?.cancel()
        if listenFD >= 0 { close(listenFD) }
        unlink(socketPath)
    }

    public static func name(prefix: String, version: Int = 1, pid: Int32 = getpid()) -> String {
        "\(prefix).v\(version).\(pid)"
    }

    /// Same contract as the macOS original: `work` runs on the main queue, the port's queue waits.
    public static func replyFromMainQueue(deadline: DispatchTime, fallback: Data,
                                          _ work: @escaping (@escaping (Data) -> Void) -> Void) -> Data {
        final class Result {
            private let lock = NSLock()
            private var data: Data?
            private var delivered = false
            func deliver(_ data: Data) -> Bool {
                lock.lock(); defer { lock.unlock() }
                guard !delivered else { return false }
                delivered = true
                self.data = data
                return true
            }
            func take() -> Data? {
                lock.lock(); defer { lock.unlock() }
                return data
            }
        }
        let result = Result()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            if DispatchTime.now() < deadline {
                work { data in
                    if result.deliver(data) { done.signal() }
                }
            } else {
                done.signal()
            }
        }
        return done.wait(timeout: deadline) == .success ? (result.take() ?? fallback) : fallback
    }

    private func acceptPending() {
        while true {
            let client = accept(listenFD, nil, nil)
            if client < 0 { return }
            queue.async { [handler] in
                MessagePortSocket.serve(client, handler: handler)
            }
        }
    }
}

public enum MessagePortClient {
    public enum Failure: Error, Equatable {
        case notListening
        case sendFailed(Int32)
    }

    public static func isListening(_ name: String) -> Bool {
        let fd = MessagePortSocket.openConnection(path: MessagePortSocket.path(for: name))
        if fd >= 0 { close(fd) }
        return fd >= 0
    }

    public static func waitForServer(_ name: String, timeout: TimeInterval,
                                     keepWaiting: @escaping () -> Bool = { true },
                                     completion: @escaping (Bool) -> Void) {
        let deadline = Date().addingTimeInterval(timeout)
        func tick() {
            if isListening(name) { completion(true); return }
            guard Date() < deadline, keepWaiting() else { completion(isListening(name)); return }
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(50)) { tick() }
        }
        tick()
    }

    public static func send(_ payload: Data, to name: String, messageID: Int32 = 1,
                            sendTimeout: TimeInterval? = nil, timeout: TimeInterval) -> Result<Data, Failure> {
        let fd = MessagePortSocket.openConnection(path: MessagePortSocket.path(for: name))
        guard fd >= 0 else { return .failure(.notListening) }
        defer { close(fd) }
        let recvSeconds = timeout
        var recvTimeval = timeval(tv_sec: Int(recvSeconds), tv_usec: Int((recvSeconds - Double(Int(recvSeconds))) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &recvTimeval, socklen_t(MemoryLayout<timeval>.size))
        let sendSeconds = sendTimeout ?? timeout
        var sendTimeval = timeval(tv_sec: Int(sendSeconds), tv_usec: Int((sendSeconds - Double(Int(sendSeconds))) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &sendTimeval, socklen_t(MemoryLayout<timeval>.size))
        var header = (messageID.littleEndian, UInt32(payload.count).littleEndian)
        let written = withUnsafeBytes(of: &header) { bytes in
            MessagePortSocket.writeAll(fd, bytes.baseAddress!, bytes.count)
        }
        guard written else { return .failure(.sendFailed(errno)) }
        let bodyWritten = payload.withUnsafeBytes { bytes in
            MessagePortSocket.writeAll(fd, bytes.baseAddress!, bytes.count)
        }
        guard bodyWritten else { return .failure(.sendFailed(errno)) }
        // The reply is a length plus the payload (no message id: one request per connection).
        var replyLength: UInt32 = 0
        guard withUnsafeMutableBytes(of: &replyLength, { bytes in
            MessagePortSocket.readAll(fd, bytes.baseAddress!, bytes.count)
        }) else { return .failure(.sendFailed(errno)) }
        let length = Int(UInt32(littleEndian: replyLength))
        guard length <= 64 * 1024 * 1024 else { return .failure(.sendFailed(0)) }
        var reply = Data(count: length)
        guard reply.withUnsafeMutableBytes({ bytes in
            MessagePortSocket.readAll(fd, bytes.baseAddress!, bytes.count)
        }) else { return .failure(.sendFailed(errno)) }
        return .success(reply)
    }
}

/// Shared socket helpers of the Linux backend. One request per connection:
/// Int32 message id, UInt32 payload length, payload; the reply is a length plus the payload.
enum MessagePortSocket {
    static func path(for name: String) -> String {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sock").path
    }

    static func makeAddress(_ path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let utf8 = Array(path.utf8)
        guard utf8.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            utf8.withUnsafeBytes { memcpy(pointer, $0.baseAddress!, utf8.count) }
        }
        return address
    }

    static func openConnection(path: String) -> Int32 {
        guard var address = makeAddress(path) else { return -1 }
        let fd = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
        guard fd >= 0 else { return -1 }
        let result = withUnsafePointer(to: &address) { addressPointer in
            addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if result != 0 { close(fd); return -1 }
        return fd
    }

    /// Reads exactly `count` bytes; false on EOF, timeout or error.
    static func readAll(_ fd: Int32, _ buffer: UnsafeMutableRawPointer, _ count: Int) -> Bool {
        var offset = 0
        while offset < count {
            let n = read(fd, buffer.advanced(by: offset), count - offset)
            if n > 0 {
                offset += n
            } else if n == 0 {
                return false
            } else if errno == EINTR {
                continue
            } else {
                return false
            }
        }
        return true
    }

    static func writeAll(_ fd: Int32, _ buffer: UnsafeRawPointer, _ count: Int) -> Bool {
        var offset = 0
        while offset < count {
            let n = write(fd, buffer.advanced(by: offset), count - offset)
            if n > 0 {
                offset += n
            } else if n < 0, errno == EINTR {
                continue
            } else {
                return false
            }
        }
        return true
    }

    /// Serves one connection: requests until EOF, one synchronous reply each.
    static func serve(_ fd: Int32, handler: (Int32, Data) -> Data) {
        defer { close(fd) }
        var header = (Int32(0).littleEndian, UInt32(0).littleEndian)
        while withUnsafeMutableBytes(of: &header, { bytes in
            readAll(fd, bytes.baseAddress!, bytes.count)
        }) {
            let messageID = Int32(littleEndian: header.0)
            let length = Int(UInt32(littleEndian: header.1))
            guard length <= 64 * 1024 * 1024 else { return }
            var payload = Data(count: length)
            guard payload.withUnsafeMutableBytes({ bytes in
                readAll(fd, bytes.baseAddress!, bytes.count)
            }) else { return }
            let reply = handler(messageID, payload)
            var replyHeader = UInt32(reply.count).littleEndian
            guard withUnsafeBytes(of: &replyHeader, { bytes in
                writeAll(fd, bytes.baseAddress!, bytes.count)
            }) else { return }
            guard reply.withUnsafeBytes({ bytes in
                writeAll(fd, bytes.baseAddress!, bytes.count)
            }) else { return }
        }
    }
}
#endif
