import Foundation
import SystemConfiguration

/// Basic information about an active network interface.
struct NetworkInterfaceInfo {
    /// The network service name, e.g. "Wi-Fi". Matches what System Settings
    /// and `networksetup` call this interface, so it doubles as the
    /// identifier used to apply profiles.
    let serviceName: String
    /// BSD hardware identifier, e.g. "en0".
    let hardwareID: String
    /// Current IPv4 address, if any.
    let ipAddress: String?
    /// Current IPv4 subnet mask, if any.
    let subnetMask: String?
    /// Current IPv4 router (gateway) address, if any.
    let router: String?
    /// How this interface currently gets its IPv4 address.
    let configMethod: IPConfigMethod
}

/// How the primary interface currently gets its IPv4 address.
enum IPConfigMethod {
    case dhcp
    case manual
    case unknown
}

/// Overall connection state used to drive the status bar icon.
enum ConnectionState {
    case disconnected
    case connected(IPConfigMethod)
}

/// Watches the system's network configuration using SCDynamicStore and
/// reports the active interfaces plus the current connection state.
/// The `onChange` callback fires whenever the network configuration changes
/// so the caller can refresh the menu and status icon in real time.
final class NetworkMonitor {

    var onChange: (() -> Void)?

    private var store: SCDynamicStore?
    private var runLoopSource: CFRunLoopSource?

    func start() {
        var context = SCDynamicStoreContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        guard let store = SCDynamicStoreCreate(
            nil,
            "IPChange" as CFString,
            { _, _, info in
                guard let info = info else { return }
                let monitor = Unmanaged<NetworkMonitor>.fromOpaque(info).takeUnretainedValue()
                monitor.onChange?()
            },
            &context
        ) else {
            return
        }

        let patterns = [
            "State:/Network/Global/IPv4",
            "State:/Network/Interface/.*/IPv4",
            "State:/Network/Interface/.*/Link",
            "State:/Network/Service/.*/IPv4"
        ] as CFArray

        SCDynamicStoreSetNotificationKeys(store, nil, patterns)

        guard let source = SCDynamicStoreCreateRunLoopSource(nil, store, 0) else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)

        self.store = store
        self.runLoopSource = source
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        runLoopSource = nil
        store = nil
    }

    /// Returns every currently active (link-up, configured) network interface.
    func activeInterfaces() -> [NetworkInterfaceInfo] {
        guard let services = allNetworkServices() else { return [] }

        var result: [NetworkInterfaceInfo] = []
        for service in services {
            guard SCNetworkServiceGetEnabled(service),
                  let interface = SCNetworkServiceGetInterface(service),
                  let bsdName = SCNetworkInterfaceGetBSDName(interface) as String? else {
                continue
            }
            guard let serviceID = SCNetworkServiceGetServiceID(service) as String?,
                  let ipv4State = ipv4State(forServiceID: serviceID) else {
                continue
            }

            let serviceName = (SCNetworkServiceGetName(service) as String?)
                ?? (SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?)
                ?? bsdName
            let addresses = ipv4State["Addresses"] as? [String]
            let subnetMasks = ipv4State["SubnetMasks"] as? [String]
            result.append(NetworkInterfaceInfo(
                serviceName: serviceName,
                hardwareID: bsdName,
                ipAddress: addresses?.first,
                subnetMask: subnetMasks?.first,
                router: ipv4State["Router"] as? String,
                configMethod: configMethod(for: service)
            ))
        }
        return result
    }

    /// Returns the overall connection state, based on the system's primary
    /// (default route) network interface.
    func currentConnectionState() -> ConnectionState {
        guard let primaryInterfaceID = primaryInterfaceBSDName() else {
            return .disconnected
        }
        return .connected(configMethod(forBSDName: primaryInterfaceID))
    }

    /// Returns the BSD name of the system's current primary (default route)
    /// interface, or nil if there isn't one.
    func primaryInterfaceBSDName() -> String? {
        guard let store = store ?? SCDynamicStoreCreate(nil, "IPChange" as CFString, nil, nil),
              let globalState = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
              let primaryInterface = globalState["PrimaryInterface"] as? String else {
            return nil
        }
        return primaryInterface
    }

    // MARK: - Private helpers

    private func allNetworkServices() -> [SCNetworkService]? {
        guard let prefs = SCPreferencesCreate(nil, "IPChange" as CFString, nil),
              let set = SCNetworkSetCopyCurrent(prefs) else {
            return nil
        }
        return SCNetworkSetCopyServices(set) as? [SCNetworkService]
    }

    /// Returns the "State:/Network/Service/<serviceID>/IPv4" dictionary for
    /// a service, or nil if it currently has no IPv4 state (i.e. it is not
    /// active). Unlike the per-interface state key, this one also carries
    /// the "Router" entry when a gateway is configured.
    private func ipv4State(forServiceID serviceID: String) -> [String: Any]? {
        guard let store = store ?? SCDynamicStoreCreate(nil, "IPChange" as CFString, nil, nil) else {
            return nil
        }
        let key = "State:/Network/Service/\(serviceID)/IPv4" as CFString
        return SCDynamicStoreCopyValue(store, key) as? [String: Any]
    }

    private func configMethod(forBSDName bsdName: String) -> IPConfigMethod {
        guard let services = allNetworkServices() else { return .unknown }

        for service in services {
            guard let interface = SCNetworkServiceGetInterface(service),
                  SCNetworkInterfaceGetBSDName(interface) as String? == bsdName else {
                continue
            }
            return configMethod(for: service)
        }
        return .unknown
    }

    private func configMethod(for service: SCNetworkService) -> IPConfigMethod {
        guard let ipv4Protocol = SCNetworkServiceCopyProtocol(service, kSCNetworkProtocolTypeIPv4),
              let configuration = SCNetworkProtocolGetConfiguration(ipv4Protocol) as? [String: Any],
              let method = configuration[kSCPropNetIPv4ConfigMethod as String] as? String else {
            return .unknown
        }
        return method == (kSCValNetIPv4ConfigMethodDHCP as String) ? .dhcp : .manual
    }
}
