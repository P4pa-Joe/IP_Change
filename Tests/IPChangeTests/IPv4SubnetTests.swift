import XCTest
@testable import IP_Change

final class IPv4SubnetTests: XCTestCase {

    // MARK: - toUInt32

    func testToUInt32ParsesValidAddress() {
        XCTAssertEqual(IPv4Subnet.toUInt32("192.168.1.1"), 0xC0A80101)
    }

    func testToUInt32RejectsOutOfRangeOctet() {
        XCTAssertNil(IPv4Subnet.toUInt32("192.168.1.256"))
    }

    func testToUInt32RejectsWrongComponentCount() {
        XCTAssertNil(IPv4Subnet.toUInt32("192.168.1"))
        XCTAssertNil(IPv4Subnet.toUInt32("192.168.1.1.1"))
    }

    func testToUInt32RejectsNonNumericComponent() {
        XCTAssertNil(IPv4Subnet.toUInt32("192.168.1.abc"))
    }

    // MARK: - toString

    func testToStringRoundTripsWithToUInt32() {
        let value: UInt32 = 0xC0A80101
        XCTAssertEqual(IPv4Subnet.toString(value), "192.168.1.1")
        XCTAssertEqual(IPv4Subnet.toUInt32(IPv4Subnet.toString(value)), value)
    }

    // MARK: - init

    func testInitFailsOnInvalidAddress() {
        XCTAssertNil(IPv4Subnet(ipAddress: "not-an-ip", subnetMask: "255.255.255.0"))
    }

    // MARK: - hostAddresses

    func testHostAddressesExcludesNetworkAndBroadcast() {
        let subnet = IPv4Subnet(ipAddress: "192.168.1.10", subnetMask: "255.255.255.0")
        let hosts = subnet?.hostAddresses(limit: 1024)

        XCTAssertEqual(hosts?.count, 254)
        XCTAssertEqual(hosts?.first, "192.168.1.1")
        XCTAssertEqual(hosts?.last, "192.168.1.254")
        XCTAssertFalse(hosts?.contains("192.168.1.0") ?? true)
        XCTAssertFalse(hosts?.contains("192.168.1.255") ?? true)
    }

    func testHostAddressesRespectsLimit() {
        let subnet = IPv4Subnet(ipAddress: "10.0.0.1", subnetMask: "255.255.0.0")
        XCTAssertEqual(subnet?.hostAddresses(limit: 5).count, 5)
    }

    func testHostAddressesEmptyForPointToPointMask() {
        // A /31 leaves no room for a usable host under this scheme, since
        // network and broadcast already account for both addresses.
        let subnet = IPv4Subnet(ipAddress: "10.0.0.1", subnetMask: "255.255.255.254")
        XCTAssertEqual(subnet?.hostAddresses(limit: 1024), [])
    }
}
