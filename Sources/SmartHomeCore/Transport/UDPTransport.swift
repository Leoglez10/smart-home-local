import Foundation
#if canImport(Darwin)
import Darwin
#endif

public struct Datagram: Equatable, Sendable {
    public var payload: Data
    public var sender: String

    public init(payload: Data, sender: String) {
        self.payload = payload
        self.sender = sender
    }
}

/// UDP I/O used by drivers and discovery. Abstracted so codecs and providers are testable without a network.
public protocol UDPTransport: Sendable {
    /// Sends `payload` to the broadcast address(es) `sends` times, `interval` seconds apart,
    /// and collects every reply received during `listen` seconds.
    func broadcast(_ payload: Data, port: UInt16, sends: Int, interval: TimeInterval, listen: TimeInterval) async throws -> [Datagram]
    /// Unicast request/response. Returns nil on timeout.
    func request(_ payload: Data, host: String, port: UInt16, timeout: TimeInterval) async throws -> Data?
}

/// BSD-socket implementation. Broadcast goes to 255.255.255.255 and to each active
/// IPv4 interface's directed broadcast address; it never sweeps individual hosts.
public struct BSDUDPTransport: UDPTransport {
    public init() {}

    public func broadcast(_ payload: Data, port: UInt16, sends: Int, interval: TimeInterval, listen: TimeInterval) async throws -> [Datagram] {
        try await Task.detached {
            try Self.runBroadcast(payload, port: port, sends: sends, interval: interval, listen: listen)
        }.value
    }

    public func request(_ payload: Data, host: String, port: UInt16, timeout: TimeInterval) async throws -> Data? {
        try await Task.detached {
            try Self.runRequest(payload, host: host, port: port, timeout: timeout)
        }.value
    }

    // MARK: - Blocking implementation

    private static func runBroadcast(_ payload: Data, port: UInt16, sends: Int, interval: TimeInterval, listen: TimeInterval) throws -> [Datagram] {
        let fd = try openSocket(broadcast: true)
        defer { close(fd) }
        let targets = Array(Set(["255.255.255.255"] + directedBroadcastAddresses())).sorted()

        var replies: [Datagram] = []
        let start = Date()
        let deadline = start.addingTimeInterval(listen)
        var sent = 0
        var nextSend = start
        while true {
            let now = Date()
            if now >= deadline { break }
            if sent < max(sends, 1), now >= nextSend {
                // One unreachable interface (e.g. a link-local 169.254.x.x adapter) must not
                // abort discovery on the others; fail only when every target fails.
                var failures: [String] = []
                for target in targets {
                    do { try send(fd, payload, to: target, port: port) }
                    catch { failures.append(String(describing: error)) }
                }
                if failures.count == targets.count {
                    throw SmartDeviceError.transport(failures.joined(separator: "; "))
                }
                sent += 1
                nextSend = nextSend.addingTimeInterval(interval)
            }
            let wakeAt = sent < max(sends, 1) ? min(deadline, nextSend) : deadline
            replies += receive(fd, until: wakeAt)
        }
        return replies
    }

    private static func runRequest(_ payload: Data, host: String, port: UInt16, timeout: TimeInterval) throws -> Data? {
        let fd = try openSocket(broadcast: false)
        defer { close(fd) }
        let deadline = Date().addingTimeInterval(timeout)
        // UDP is lossy: resend every 0.5 s until a reply from `host` arrives (pywizlight does the same).
        var nextSend = Date()
        while Date() < deadline {
            if Date() >= nextSend {
                try send(fd, payload, to: host, port: port)
                nextSend = Date().addingTimeInterval(0.5)
            }
            for reply in receive(fd, until: min(deadline, nextSend), stopAfterFirst: true) where reply.sender == host {
                return reply.payload
            }
        }
        return nil
    }

    private static func openSocket(broadcast: Bool) throws -> Int32 {
        let fd = socket(AF_INET, SOCK_DGRAM, Int32(IPPROTO_UDP))
        guard fd >= 0 else { throw SmartDeviceError.transport("socket() failed: errno \(errno)") }
        if broadcast {
            var yes: Int32 = 1
            guard setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
                close(fd)
                throw SmartDeviceError.transport("SO_BROADCAST failed: errno \(errno)")
            }
        }
        var local = sockaddr_in()
        local.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        local.sin_family = sa_family_t(AF_INET)
        local.sin_port = 0 // ephemeral port
        local.sin_addr = in_addr(s_addr: INADDR_ANY)
        let bound = withUnsafePointer(to: &local) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0 else {
            close(fd)
            throw SmartDeviceError.transport("bind() failed: errno \(errno)")
        }
        return fd
    }

    private static func send(_ fd: Int32, _ payload: Data, to host: String, port: UInt16) throws {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else {
            throw SmartDeviceError.transport("invalid IPv4 address: \(host)")
        }
        let result = payload.withUnsafeBytes { bytes in
            withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, bytes.baseAddress, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        if result < 0 {
            throw SmartDeviceError.transport("sendto \(host):\(port) failed: errno \(errno)")
        }
    }

    private static func receive(_ fd: Int32, until deadline: Date, stopAfterFirst: Bool = false) -> [Datagram] {
        var replies: [Datagram] = []
        while true {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { break }
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&pfd, 1, Int32(max(1, remaining * 1000)))
            if ready <= 0 { break }
            var buffer = [UInt8](repeating: 0, count: 4096)
            var sender = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &sender) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(fd, &buffer, buffer.count, 0, $0, &length) }
            }
            guard count > 0 else { continue }
            var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            inet_ntop(AF_INET, &sender.sin_addr, &text, socklen_t(INET_ADDRSTRLEN))
            let host = String(decoding: text.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            replies.append(Datagram(payload: Data(buffer.prefix(count)), sender: host))
            if stopAfterFirst { break }
        }
        return replies
    }

    /// Directed broadcast address of every up, non-loopback IPv4 interface (e.g. 192.168.1.255).
    static func directedBroadcastAddresses() -> [String] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        var result: [String] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = pointer.pointee
            let flags = Int32(ifa.ifa_flags)
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == sa_family_t(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_BROADCAST != 0, flags & IFF_LOOPBACK == 0,
                  let broadcast = ifa.ifa_dstaddr else { continue }
            var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            broadcast.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
                var a = sin.pointee.sin_addr
                _ = inet_ntop(AF_INET, &a, &text, socklen_t(INET_ADDRSTRLEN))
            }
            let string = String(decoding: text.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            if !string.isEmpty { result.append(string) }
        }
        return result
    }
}
