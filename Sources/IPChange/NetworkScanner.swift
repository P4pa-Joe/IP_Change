import Foundation
import Darwin

/// A single host discovered on the local subnet.
struct ScanHost: Equatable {
    var ipAddress: String
    var macAddress: String?
    var hostname: String?
    /// Ports from `NetworkScanner.wellKnownPorts` found open on this host,
    /// e.g. so the "connect" menu can only offer protocols that will work.
    var openPorts: Set<Int> = []
}

/// Performs a ping sweep across an interface's subnet, reads MAC addresses
/// from the ARP table for hosts that respond, and resolves hostnames for
/// them. Reports progress and discoveries incrementally so a window can
/// update live while the scan runs.
final class NetworkScanner {

    private static let maxHostsPerScan = 1024
    private static let maxConcurrentPings = 24
    /// The ports the "connect" quick actions know how to use — kept here
    /// alongside the sweep so a host's `openPorts` reflects exactly what a
    /// probe was attempted for.
    static let wellKnownPorts: [UInt16] = [80, 443, 22, 23]

    private var isCancelled = false
    private let hostnameQueue = DispatchQueue(label: "IPChange.NetworkScanner.hostname", attributes: .concurrent)
    private let portsQueue = DispatchQueue(label: "IPChange.NetworkScanner.ports", attributes: .concurrent)

    func cancel() {
        isCancelled = true
    }

    /// - Parameters:
    ///   - onProgress: called on the main thread as hosts are tested.
    ///   - onHostFound: called on the main thread as soon as a host answers
    ///     a ping (MAC address included if the ARP table already has it;
    ///     hostname is filled in later via `onHostnameResolved`).
    ///   - onHostnameResolved: called on the main thread once a reverse
    ///     lookup (unicast DNS or mDNS/Bonjour for `.local` names) succeeds
    ///     for a previously-found host.
    ///   - onPortsResolved: called on the main thread once at least one of
    ///     `wellKnownPorts` is confirmed open on a previously-found host.
    ///   - completion: called on the main thread once every host has been
    ///     tested (or the scan was cancelled).
    func scan(
        interfaceIPAddress: String,
        subnetMask: String,
        onProgress: @escaping (_ tested: Int, _ total: Int, _ found: Int) -> Void,
        onHostFound: @escaping (ScanHost) -> Void,
        onHostnameResolved: @escaping (_ ipAddress: String, _ hostname: String) -> Void,
        onPortsResolved: @escaping (_ ipAddress: String, _ openPorts: Set<Int>) -> Void,
        completion: @escaping () -> Void
    ) {
        isCancelled = false

        guard let subnet = IPv4Subnet(ipAddress: interfaceIPAddress, subnetMask: subnetMask) else {
            completion()
            return
        }

        let hosts = subnet.hostAddresses(limit: Self.maxHostsPerScan).filter { $0 != interfaceIPAddress }
        let total = hosts.count
        guard total > 0 else {
            completion()
            return
        }

        var tested = 0
        var found = 0
        let counterLock = NSLock()
        let semaphore = DispatchSemaphore(value: Self.maxConcurrentPings)
        let group = DispatchGroup()
        let sweepQueue = DispatchQueue(label: "IPChange.NetworkScanner.sweep", attributes: .concurrent)

        for host in hosts {
            group.enter()
            sweepQueue.async { [weak self] in
                semaphore.wait()
                defer {
                    semaphore.signal()
                    group.leave()
                }
                guard let self, !self.isCancelled else { return }

                let reachable = Self.ping(host)

                counterLock.lock()
                tested += 1
                if reachable { found += 1 }
                let testedSnapshot = tested
                let foundSnapshot = found
                counterLock.unlock()

                DispatchQueue.main.async { onProgress(testedSnapshot, total, foundSnapshot) }

                guard reachable, !self.isCancelled else { return }

                let mac = Self.arpLookup(host)
                let scanHost = ScanHost(ipAddress: host, macAddress: mac, hostname: nil)
                DispatchQueue.main.async { onHostFound(scanHost) }

                self.hostnameQueue.async {
                    guard !self.isCancelled, let hostname = Self.resolveHostname(host) else { return }
                    DispatchQueue.main.async { onHostnameResolved(host, hostname) }
                }

                self.portsQueue.async {
                    guard !self.isCancelled else { return }
                    let openPorts = Set(Self.wellKnownPorts.filter { Self.isPortOpen(host, port: $0) }.map { Int($0) })
                    guard !self.isCancelled, !openPorts.isEmpty else { return }
                    DispatchQueue.main.async { onPortsResolved(host, openPorts) }
                }
            }
        }

        group.notify(queue: .main) {
            completion()
        }
    }

    // MARK: - Private helpers

    private static func ping(_ host: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/ping")
        process.arguments = ["-c", "1", "-t", "1", host]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func arpLookup(_ host: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
        process.arguments = ["-n", host]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return nil }
        return extractMACAddress(from: output)
    }

    private static func extractMACAddress(from text: String) -> String? {
        guard let range = text.range(of: #"([0-9A-Fa-f]{1,2}:){5}[0-9A-Fa-f]{1,2}"#, options: .regularExpression) else {
            return nil
        }
        return String(text[range])
    }

    /// Checks whether a TCP port accepts connections, via a non-blocking
    /// `connect()` bounded by `poll()` rather than waiting out the OS's
    /// full connect timeout (tens of seconds) on filtered ports.
    private static func isPortOpen(_ host: String, port: UInt16, timeoutSeconds: Double = 0.3) -> Bool {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else { return false }

        let sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard sock >= 0 else { return false }
        defer { Darwin.close(sock) }

        let flags = fcntl(sock, F_GETFL, 0)
        _ = fcntl(sock, F_SETFL, flags | O_NONBLOCK)

        let connectResult = withUnsafePointer(to: &address) { pointer -> Int32 in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                connect(sock, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if connectResult == 0 { return true }
        guard errno == EINPROGRESS else { return false }

        var pollDescriptor = pollfd(fd: sock, events: Int16(POLLOUT), revents: 0)
        guard poll(&pollDescriptor, 1, Int32(timeoutSeconds * 1000)) > 0 else { return false }

        var socketError: Int32 = 0
        var errorLength = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(sock, SOL_SOCKET, SO_ERROR, &socketError, &errorLength)
        return socketError == 0
    }

    /// Reverse-resolves a hostname for a local IPv4 address. macOS routes
    /// both unicast DNS and multicast DNS (Bonjour, `.local` names) through
    /// the same system resolver, so a plain `getnameinfo` call is enough to
    /// pick up mDNS-advertised hostnames for hosts on the local subnet.
    private static func resolveHostname(_ ipAddress: String) -> String? {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        guard inet_pton(AF_INET, ipAddress, &address.sin_addr) == 1 else { return nil }

        var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = withUnsafePointer(to: &address) { pointer -> Int32 in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                getnameinfo(
                    sockaddrPointer,
                    socklen_t(MemoryLayout<sockaddr_in>.size),
                    &hostBuffer,
                    socklen_t(hostBuffer.count),
                    nil,
                    0,
                    NI_NAMEREQD
                )
            }
        }
        guard result == 0 else { return nil }
        let name = String(cString: hostBuffer)
        return name.isEmpty ? nil : name
    }
}
