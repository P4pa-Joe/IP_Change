import Foundation

/// Owns the live state of one interface's network scan (running sweep,
/// hosts found so far, status text), independent of how it's displayed.
final class ScanSession {

    private(set) var hosts: [ScanHost] = []
    private(set) var isScanning = false
    private(set) var statusText = "Not scanned yet."

    /// Called on the main thread whenever `hosts`, `isScanning`, or
    /// `statusText` change.
    var onUpdate: (() -> Void)?

    private let interface: NetworkInterfaceInfo
    private let scanner = NetworkScanner()

    init(interface: NetworkInterfaceInfo) {
        self.interface = interface
    }

    func cancel() {
        scanner.cancel()
    }

    func start() {
        guard !isScanning else { return }
        guard let ip = interface.ipAddress, let mask = interface.subnetMask, !ip.isEmpty, !mask.isEmpty else {
            statusText = "This interface has no IPv4 address to scan."
            onUpdate?()
            return
        }

        hosts = []
        isScanning = true
        statusText = "Starting scan…"
        onUpdate?()

        scanner.scan(
            interfaceIPAddress: ip,
            subnetMask: mask,
            onProgress: { [weak self] tested, total, found in
                guard let self else { return }
                self.statusText = "Scanning… \(tested)/\(total) tested, \(found) found"
                self.onUpdate?()
            },
            onHostFound: { [weak self] host in
                guard let self else { return }
                self.hosts.append(host)
                self.sortHosts()
                self.onUpdate?()
            },
            onHostnameResolved: { [weak self] ipAddress, hostname in
                guard let self, let index = self.hosts.firstIndex(where: { $0.ipAddress == ipAddress }) else { return }
                self.hosts[index].hostname = hostname
                self.onUpdate?()
            },
            completion: { [weak self] in
                guard let self else { return }
                self.isScanning = false
                self.statusText = "Found \(self.hosts.count) host\(self.hosts.count == 1 ? "" : "s")."
                self.onUpdate?()
            }
        )
    }

    private func sortHosts() {
        hosts.sort { (IPv4Subnet.toUInt32($0.ipAddress) ?? 0) < (IPv4Subnet.toUInt32($1.ipAddress) ?? 0) }
    }
}
