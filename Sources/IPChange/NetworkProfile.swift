import Foundation

/// A saved network configuration that can be applied to an interface.
struct NetworkProfile: Codable, Identifiable, Equatable {

    enum Mode: String, Codable, CaseIterable {
        case dhcp = "DHCP"
        case manual = "Static"
    }

    var id: UUID
    var name: String
    var mode: Mode
    var ipAddress: String
    var subnetMask: String
    var router: String
    var dnsServers: [String]

    init(
        id: UUID = UUID(),
        name: String,
        mode: Mode,
        ipAddress: String = "",
        subnetMask: String = "",
        router: String = "",
        dnsServers: [String] = []
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.ipAddress = ipAddress
        self.subnetMask = subnetMask
        self.router = router
        self.dnsServers = dnsServers
    }

    /// Captures the live configuration of an interface as a profile, so it
    /// can be restored later (used for automatic rollback).
    static func snapshotCurrent(for interface: NetworkInterfaceInfo) -> NetworkProfile {
        NetworkProfile(
            name: "Previous Configuration",
            mode: interface.configMethod == .dhcp ? .dhcp : .manual,
            ipAddress: interface.ipAddress ?? "",
            subnetMask: interface.subnetMask ?? "",
            router: interface.router ?? "",
            dnsServers: NetworkConfigurator.currentDNSServers(forService: interface.serviceName)
        )
    }
}
