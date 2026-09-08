import AppKit

/// Builds and live-updates the "Scan Network" submenu for one interface:
/// starts a ping/ARP/mDNS sweep the first time the submenu opens, and
/// keeps the menu's contents in sync as hosts are discovered. Results are
/// shown as native menu items (rather than a separate window) so the user
/// never has to leave the menu bar.
final class ScanMenuController: NSObject, NSMenuDelegate {

    private let session: ScanSession
    private var hasStartedOnce = false

    /// The most recently vended menu instance — the one currently (or most
    /// recently) installed as a submenu. Live updates from the scan are
    /// applied to this instance in place.
    ///
    /// A fresh `NSMenu` is built on every call to `makeMenu()` rather than
    /// handing out one long-lived instance, because the caller's own menu
    /// (the whole status-bar menu) gets fully torn down and rebuilt each
    /// time it opens. Reassigning the *same* NSMenu as a submenu again
    /// while AppKit is mid-transition displaying/replacing the previous
    /// tree crashes with a "menu already has a supermenu" assertion. Only
    /// the scan state (`ScanSession`) needs to survive across rebuilds —
    /// the menu object itself doesn't.
    private weak var currentMenu: NSMenu?

    init(interface: NetworkInterfaceInfo) {
        session = ScanSession(interface: interface)
        super.init()

        session.onUpdate = { [weak self] in
            DispatchQueue.main.async {
                self?.refreshCurrentMenu()
            }
        }
    }

    func cancel() {
        session.cancel()
    }

    /// Builds a fresh menu populated with the current scan state. Call
    /// this every time the "Scan Network" item needs a submenu — never
    /// reuse a previously returned instance as a submenu again.
    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        populate(menu)
        currentMenu = menu
        return menu
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        guard !hasStartedOnce else { return }
        hasStartedOnce = true
        session.start()
    }

    // MARK: - Menu content

    private func refreshCurrentMenu() {
        guard let menu = currentMenu else { return }
        populate(menu)
    }

    private func populate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(.infoItem(title: session.statusText))

        if !session.hosts.isEmpty {
            menu.addItem(.separator())
            for host in session.hosts {
                menu.addItem(hostItem(for: host))
            }
        }

        menu.addItem(.separator())

        let rescanItem = NSMenuItem(title: "Rescan", action: #selector(rescanTapped), keyEquivalent: "")
        rescanItem.target = self
        rescanItem.isEnabled = !session.isScanning
        menu.addItem(rescanItem)
    }

    private func hostItem(for host: ScanHost) -> NSMenuItem {
        var title = host.ipAddress
        if let hostname = host.hostname {
            title += "  \(hostname)"
        }
        if let mac = host.macAddress {
            title += "  (\(mac))"
        }

        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = connectSubmenu(for: host)
        return item
    }

    /// Only offers protocols whose port was confirmed open on this host —
    /// no point suggesting SSH to something that isn't listening on 22.
    private func connectSubmenu(for host: ScanHost) -> NSMenu {
        let submenu = NSMenu()
        submenu.autoenablesItems = false

        let entries: [(title: String, port: Int, action: Selector)] = [
            ("HTTP", 80, #selector(connectHTTP(_:))),
            ("HTTPS", 443, #selector(connectHTTPS(_:))),
            ("SSH", 22, #selector(connectSSH(_:))),
            ("Telnet", 23, #selector(connectTelnet(_:)))
        ]
        for (title, port, action) in entries where host.openPorts.contains(port) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = host
            submenu.addItem(item)
        }

        if submenu.items.isEmpty {
            let item = NSMenuItem(title: "No Open Ports Detected", action: nil, keyEquivalent: "")
            item.isEnabled = false
            submenu.addItem(item)
        }

        return submenu
    }

    // MARK: - Actions

    @objc private func rescanTapped() {
        session.start()
    }

    @objc private func connectHTTP(_ sender: NSMenuItem) {
        guard let host = sender.representedObject as? ScanHost else { return }
        HostConnector.openHTTP(host)
    }

    @objc private func connectHTTPS(_ sender: NSMenuItem) {
        guard let host = sender.representedObject as? ScanHost else { return }
        HostConnector.openHTTPS(host)
    }

    @objc private func connectSSH(_ sender: NSMenuItem) {
        guard let host = sender.representedObject as? ScanHost else { return }
        HostConnector.openSSH(host)
    }

    @objc private func connectTelnet(_ sender: NSMenuItem) {
        guard let host = sender.representedObject as? ScanHost else { return }
        HostConnector.openTelnet(host)
    }
}
