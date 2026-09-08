import AppKit
import UserNotifications

/// Coordinates applying a saved `NetworkProfile` to a live interface:
/// confirms with the user when a remote session might be at risk, applies
/// the profile via `NetworkConfigurator`, verifies the interface stayed
/// reachable, and automatically rolls back to the previous configuration
/// on failure.
final class ProfileApplier: NSObject {

    static let shared = ProfileApplier()

    private override init() {
        super.init()
        // Only a properly bundled app (see LoginItemManager) has a bundle
        // identifier for the notification center to attach to — under
        // `swift run` this is skipped and success banners just don't show.
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func apply(_ profile: NetworkProfile, to interface: NetworkInterfaceInfo, isPrimaryInterface: Bool) {
        if isPrimaryInterface && RemoteSessionDetector.hasActiveRemoteSession() {
            guard confirmRiskyChange(interfaceName: interface.serviceName) else { return }
        }

        let previousProfile = NetworkProfile.snapshotCurrent(for: interface)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            do {
                try NetworkConfigurator.apply(profile, toService: interface.serviceName)
            } catch {
                DispatchQueue.main.async {
                    self.notifyError(
                        title: "Could Not Apply Profile",
                        message: self.describe(error)
                    )
                }
                return
            }

            if AppPreferences.shared.showSuccessNotifications {
                DispatchQueue.main.async {
                    self.postBanner(
                        title: "Profile Applied",
                        informativeText: "\"\(profile.name)\" was applied to \(interface.serviceName)."
                    )
                }
            }

            self.verifyAndRollbackIfNeeded(
                appliedProfile: profile,
                previousProfile: previousProfile,
                interface: interface
            )
        }
    }

    // MARK: - Verification & rollback

    private func verifyAndRollbackIfNeeded(
        appliedProfile: NetworkProfile,
        previousProfile: NetworkProfile,
        interface: NetworkInterfaceInfo
    ) {
        Thread.sleep(forTimeInterval: AppPreferences.shared.rollbackVerificationDelay)

        let targetHost = appliedProfile.mode == .manual
            ? appliedProfile.router
            : (NetworkConfigurator.currentRouter(forService: interface.serviceName) ?? "")

        // No gateway to check against — e.g. a point-to-point or isolated
        // static profile (no router field set), or a DHCP server that
        // doesn't hand out a router. There's nothing meaningful to verify
        // in that case, so don't second-guess a config that has no gateway
        // by design.
        guard !targetHost.isEmpty else { return }

        guard !NetworkConfigurator.isReachable(host: targetHost) else { return }

        do {
            try NetworkConfigurator.apply(previousProfile, toService: interface.serviceName)
            DispatchQueue.main.async {
                self.notifyError(
                    title: "Profile Rolled Back",
                    message: "\"\(appliedProfile.name)\" made \(interface.serviceName) unreachable, "
                        + "so the previous configuration was restored automatically."
                )
            }
        } catch {
            DispatchQueue.main.async {
                self.notifyError(
                    title: "Network Configuration Failed",
                    message: "\"\(appliedProfile.name)\" made \(interface.serviceName) unreachable, "
                        + "and restoring the previous configuration also failed: \(self.describe(error))"
                )
            }
        }
    }

    // MARK: - User interaction

    private func confirmRiskyChange(interfaceName: String) -> Bool {
        var confirmed = false
        runOnMainSync {
            let alert = NSAlert()
            alert.messageText = "Active Remote Session Detected"
            alert.informativeText = "An SSH or screen sharing session appears to be active, and "
                + "\(interfaceName) may be carrying it. Changing its network settings could "
                + "disconnect that session. Continue?"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Continue")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            confirmed = alert.runModal() == .alertFirstButtonReturn
        }
        return confirmed
    }

    private func notifyError(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    /// A non-blocking banner for the common, successful case. Silently does
    /// nothing under `swift run` (see `init`) or if the user has denied
    /// notification permission.
    private func postBanner(title: String, informativeText: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = informativeText

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private func runOnMainSync(_ block: () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.sync(execute: block)
        }
    }
}

extension ProfileApplier: UNUserNotificationCenterDelegate {
    /// Without this, UNUserNotificationCenter suppresses banners while the
    /// app is active — showing them regardless matches the old
    /// NSUserNotification behavior this replaced.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
