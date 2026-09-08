import Foundation
import Darwin

/// A single host discovered on the local subnet.
struct ScanHost: Equatable {
    var ipAddress: String
    var macAddress: String?
    var hostname: String?
}

/// Performs a ping sweep across an interface's subnet, reads MAC addresses
/// from the ARP table for hosts that respond, and resolves hostnames for
/// them. Reports progress and discoveries incrementally so a window can
/// update live while the scan runs.
final class NetworkScanner {

    private static let maxHostsPerScan = 1024
    private static let maxConcurrentPings = 24

    private var isCancelled = false
    private let hostnameQueue = DispatchQueue(label: "IPChange.NetworkScanner.hostname", attributes: .concurrent)

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
    ///   - completion: called on the main thread once every host has been
    ///     tested (or the scan was cancelled).
    func scan(
        interfaceIPAddress: String,
        subnetMask: String,
        onProgress: @escaping (_ tested: Int, _ total: Int, _ found: Int) -> Void,
        onHostFound: @escaping (ScanHost) -> Void,
        onHostnameResolved: @escaping (_ ipAddress: String, _ hostname: String) -> Void,
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
