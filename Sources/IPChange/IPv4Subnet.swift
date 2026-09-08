import Foundation

/// IPv4 CIDR math: given an interface's address and subnet mask, enumerates
/// the usable host addresses on that subnet.
struct IPv4Subnet {
    let networkAddress: UInt32
    let broadcastAddress: UInt32

    init?(ipAddress: String, subnetMask: String) {
        guard let ip = IPv4Subnet.toUInt32(ipAddress), let mask = IPv4Subnet.toUInt32(subnetMask) else {
            return nil
        }
        networkAddress = ip & mask
        broadcastAddress = networkAddress | ~mask
    }

    /// All usable host addresses (network and broadcast excluded), capped
    /// at `limit` entries so a misconfigured or very large subnet can't
    /// turn a scan into an unbounded sweep.
    func hostAddresses(limit: Int) -> [String] {
        guard broadcastAddress > networkAddress + 1 else { return [] }

        var result: [String] = []
        var current = networkAddress + 1
        let last = broadcastAddress - 1
        while current <= last && result.count < limit {
            result.append(IPv4Subnet.toString(current))
            current += 1
        }
        return result
    }

    static func toUInt32(_ address: String) -> UInt32? {
        let parts = address.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count == 4, parts.allSatisfy({ $0 <= 255 }) else { return nil }
        return parts.reduce(0) { ($0 << 8) | $1 }
    }

    static func toString(_ value: UInt32) -> String {
        "\((value >> 24) & 0xFF).\((value >> 16) & 0xFF).\((value >> 8) & 0xFF).\(value & 0xFF)"
    }
}
