import Foundation

enum NetworkConfiguratorError: Error, LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return message
        }
    }
}

/// Builds and runs the `networksetup` commands needed to read and apply
/// network profiles for a given network service.
enum NetworkConfigurator {

    /// Applies a profile to a network service.
    ///
    /// Calls `networksetup` directly, with no privilege escalation:
    /// `networksetup`'s write commands succeed for the current user
    /// without a password as long as they're an admin in the active GUI
    /// session (the same way System Settings' Network pane never prompts
    /// either). No admin account, or a non-interactive/headless session,
    /// and this will fail with a permissions error surfaced as-is.
    static func apply(_ profile: NetworkProfile, toService serviceName: String) throws {
        switch profile.mode {
        case .dhcp:
            try runMutating(["-setdhcp", serviceName])
        case .manual:
            try runMutating([
                "-setmanual", serviceName,
                profile.ipAddress, profile.subnetMask, profile.router
            ])
        }

        if profile.dnsServers.isEmpty {
            try runMutating(["-setdnsservers", serviceName, "Empty"])
        } else {
            try runMutating(["-setdnsservers", serviceName] + profile.dnsServers)
        }
    }

    /// Reads the DNS servers currently configured for a service. Read-only,
    /// no privilege elevation required.
    static func currentDNSServers(forService serviceName: String) -> [String] {
        guard let output = try? run(["-getdnsservers", serviceName]) else { return [] }
        return output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.lowercased().contains("there aren't any dns servers") }
    }

    /// Reads the router (gateway) currently reported for a service, e.g.
    /// after a DHCP lease has been renegotiated. Read-only.
    static func currentRouter(forService serviceName: String) -> String? {
        guard let output = try? run(["-getinfo", serviceName]) else { return nil }
        for line in output.split(separator: "\n") {
            guard line.hasPrefix("Router:") else { continue }
            let value = line.replacingOccurrences(of: "Router:", with: "").trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }
        return nil
    }

    /// Checks basic IPv4 reachability of a host: a successful ping, or
    /// failing that, a resolvable ARP entry. Some gateways and embedded
    /// devices block ICMP outright while still being fully reachable, so a
    /// ping failure alone isn't reliable evidence the device is actually
    /// gone — a MAC address in the ARP table proves it answered *something*
    /// on the local network. Read-only.
    static func isReachable(host: String, timeoutSeconds: Int = 2, attempts: Int = 2) -> Bool {
        guard !host.isEmpty else { return false }
        if ping(host: host, timeoutSeconds: timeoutSeconds, attempts: attempts) { return true }
        return arpLookup(host) != nil
    }

    // MARK: - Private helpers

    private static func ping(host: String, timeoutSeconds: Int, attempts: Int) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/ping")
        process.arguments = ["-c", "\(attempts)", "-t", "\(timeoutSeconds)", host]
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
        guard let output = try? run(["-n", host], executable: "/usr/sbin/arp") else { return nil }
        return output.range(of: #"([0-9A-Fa-f]{1,2}:){5}[0-9A-Fa-f]{1,2}"#, options: .regularExpression).map {
            String(output[$0])
        }
    }

    private static func runMutating(_ arguments: [String]) throws {
        let output = try run(arguments)
        try validate(output: output)
    }

    private static func run(_ arguments: [String], executable: String = "/usr/sbin/networksetup") throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return String(data: data, encoding: .utf8) ?? ""
    }

    /// `-setdhcp`, `-setmanual`, and `-setdnsservers` are silent on success;
    /// any output at all — the exact wording of `networksetup`'s error
    /// messages isn't something to rely on — means something went wrong.
    private static func validate(output: String) throws {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        throw NetworkConfiguratorError.commandFailed(trimmed)
    }
}
