import AppKit

/// Opens a quick connection to a host discovered by a network scan.
///
/// Connections always target the numeric IP address, never the resolved
/// hostname: the hostname comes from mDNS/DNS data advertised by other
/// devices on the network, so it isn't trustworthy input to shell out with.
/// The IP address is safe because it's built by our own subnet enumeration
/// (IPv4Subnet), never parsed from network responses.
enum HostConnector {

    static func openHTTP(_ host: ScanHost) {
        openInBrowser(host, scheme: "http")
    }

    static func openHTTPS(_ host: ScanHost) {
        openInBrowser(host, scheme: "https")
    }

    static func openSSH(_ host: ScanHost) {
        runInTerminal(host, command: "ssh")
    }

    static func openTelnet(_ host: ScanHost) {
        runInTerminal(host, command: "telnet")
    }

    // MARK: - Private helpers

    private static func openInBrowser(_ host: ScanHost, scheme: String) {
        guard isValidIPv4(host.ipAddress), let url = URL(string: "\(scheme)://\(host.ipAddress)") else { return }
        NSWorkspace.shared.open(url)
    }

    private static func runInTerminal(_ host: ScanHost, command: String) {
        guard isValidIPv4(host.ipAddress) else { return }
        let script = "tell application \"Terminal\"\nactivate\ndo script \"\(command) \(host.ipAddress)\"\nend tell"

        var errorDict: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&errorDict)

        // A failure here is usually Terminal automation permission being
        // denied (System Settings > Privacy & Security > Automation) —
        // surface it instead of the command silently never launching.
        if let errorDict {
            let message = (errorDict[NSAppleScript.errorMessage] as? String) ?? "Unknown error."
            presentError(title: "Could Not Open \(command.uppercased())", message: message)
        }
    }

    private static func presentError(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .critical
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private static func isValidIPv4(_ address: String) -> Bool {
        let parts = address.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let value = Int(part), value >= 0, value <= 255 else { return false }
            return String(value) == part
        }
    }
}
