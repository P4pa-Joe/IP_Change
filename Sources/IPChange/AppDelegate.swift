import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private let networkMonitor = NetworkMonitor()

    private var profilesWindowController: ProfilesWindowController?
    private var preferencesWindowController: PreferencesWindowController?
    private var aboutWindowController: AboutWindowController?
    private var scanMenuControllers: [String: ScanMenuController] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        networkMonitor.onChange = { [weak self] in
            DispatchQueue.main.async {
                self?.refresh()
            }
        }
        networkMonitor.start()

        refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        networkMonitor.stop()
        scanMenuControllers.values.forEach { $0.cancel() }
    }

    // MARK: - Refresh

    private func refresh() {
        updateStatusIcon()
        rebuildMenu()
    }

    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }

        let state = networkMonitor.currentConnectionState()
        switch state {
        case .disconnected:
            button.image = NSImage(systemSymbolName: "network.slash", accessibilityDescription: "Disconnected")

        case .connected(let method):
            switch method {
            case .dhcp, .unknown:
                button.image = NSImage(systemSymbolName: "network", accessibilityDescription: "Connected (DHCP)")
            case .manual:
                button.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Connected (Static IP)")
            }
        }
        button.title = ""
        button.toolTip = "IP Change"
    }

    private func rebuildMenu() {
        guard let menu = statusItem.menu else { return }
        menu.removeAllItems()

        let interfaces = networkMonitor.activeInterfaces()
        if interfaces.isEmpty {
            let item = NSMenuItem(title: "No Active Interfaces", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            for interface in interfaces {
                let title = "\(interface.serviceName) (\(interface.hardwareID))"
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.submenu = detailsSubmenu(for: interface)
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Edit Profiles…", action: #selector(openEditProfiles), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ""))

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "About IP Change", action: #selector(openAbout), keyEquivalent: ""))

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: ""))

        for item in menu.items where item.action != nil {
            item.target = self
        }
    }

    private func detailsSubmenu(for interface: NetworkInterfaceInfo) -> NSMenu {
        let submenu = NSMenu()

        let rows = [
            ("IP Address", interface.ipAddress),
            ("Subnet Mask", interface.subnetMask),
            ("Router", interface.router)
        ]
        for (label, value) in rows {
            submenu.addItem(.infoItem(title: "\(label): \(value ?? "Not Available")"))
        }

        submenu.addItem(.separator())

        let changeProfileItem = NSMenuItem(title: "Change Profile", action: nil, keyEquivalent: "")
        changeProfileItem.submenu = changeProfileSubmenu(for: interface)
        submenu.addItem(changeProfileItem)

        let scanItem = NSMenuItem(title: "Scan Network", action: nil, keyEquivalent: "")
        scanItem.submenu = scanMenuController(for: interface).makeMenu()
        submenu.addItem(scanItem)

        return submenu
    }

    /// Returns the persistent scan controller for an interface, creating it
    /// on first use so scan progress and results survive the main menu
    /// being rebuilt every time it opens.
    private func scanMenuController(for interface: NetworkInterfaceInfo) -> ScanMenuController {
        if let existing = scanMenuControllers[interface.hardwareID] {
            return existing
        }
        let controller = ScanMenuController(interface: interface)
        scanMenuControllers[interface.hardwareID] = controller
        return controller
    }

    private func changeProfileSubmenu(for interface: NetworkInterfaceInfo) -> NSMenu {
        let submenu = NSMenu()
        let profiles = ProfileStore.shared.profiles

        if profiles.isEmpty {
            let item = NSMenuItem(title: "No Profiles", action: nil, keyEquivalent: "")
            item.isEnabled = false
            submenu.addItem(item)
        } else {
            for profile in profiles {
                let item = NSMenuItem(
                    title: profile.name,
                    action: #selector(changeProfileSelected(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = ProfileMenuSelection(profile: profile, interface: interface)
                submenu.addItem(item)
            }
        }

        return submenu
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
    }

    // MARK: - Actions

    @objc private func openEditProfiles() {
        if profilesWindowController == nil {
            profilesWindowController = ProfilesWindowController()
        }
        profilesWindowController?.show()
    }

    @objc private func changeProfileSelected(_ sender: NSMenuItem) {
        guard let selection = sender.representedObject as? ProfileMenuSelection else { return }
        let isPrimary = networkMonitor.primaryInterfaceBSDName() == selection.interface.hardwareID
        ProfileApplier.shared.apply(selection.profile, to: selection.interface, isPrimaryInterface: isPrimary)
    }

    @objc private func openPreferences() {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController()
        }
        preferencesWindowController?.show()
    }

    @objc private func openAbout() {
        if aboutWindowController == nil {
            aboutWindowController = AboutWindowController()
        }
        aboutWindowController?.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

/// Carries which profile should be applied to which interface through an
/// NSMenuItem's representedObject.
private struct ProfileMenuSelection {
    let profile: NetworkProfile
    let interface: NetworkInterfaceInfo
}
