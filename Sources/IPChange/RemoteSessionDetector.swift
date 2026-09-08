import Foundation

/// Best-effort detection of active remote sessions (SSH, Screen Sharing /
/// Apple Remote Desktop) on this Mac, used to warn before changing network
/// settings that could cut such a session off.
///
/// This is a heuristic, not a guarantee: it only sees connections visible
/// to the current user's `lsof`, and the caller only treats the session as
/// at risk when the interface being changed is also the current
/// default-route interface.
enum RemoteSessionDetector {

    static func hasActiveRemoteSession() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        // 22: SSH, 3283: Apple Remote Desktop, 5900: Screen Sharing / VNC.
        process.arguments = ["-nP", "-iTCP:22", "-iTCP:3283", "-iTCP:5900", "-sTCP:ESTABLISHED"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return false
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(data: data, encoding: .utf8) ?? ""
        let lines = output.split(separator: "\n").filter { !$0.isEmpty }
        // The first line is the column header; anything past it is a live connection.
        return lines.count > 1
    }
}
