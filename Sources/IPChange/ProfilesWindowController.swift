import AppKit
import UniformTypeIdentifiers

/// A real create/edit/delete interface for network profiles, backed by
/// ProfileStore. Left side: profile list. Right side: a form for the
/// selected profile, plus Import/Export.
final class ProfilesWindowController: NSWindowController {

    private let tableView = NSTableView()
    private let nameField = NSTextField()
    private let modeControl = NSSegmentedControl(labels: ["DHCP", "Static"], trackingMode: .selectOne, target: nil, action: nil)
    private let ipField = NSTextField()
    private let subnetField = NSTextField()
    private let routerField = NSTextField()
    private let dnsField = NSTextField()

    private var profiles: [NetworkProfile] = []
    private var selectedProfileID: UUID?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 300),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Edit Profiles"
        window.center()
        window.isReleasedWhenClosed = false

        self.init(window: window)
        buildUI()
        reloadProfiles()
    }

    func show() {
        reloadProfiles()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - UI construction

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = tableView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.widthAnchor.constraint(equalToConstant: 200).isActive = true

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.title = "Profiles"
        column.width = 180
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowSizeStyle = .default

        let addButton = NSButton(title: "+", target: self, action: #selector(addProfile))
        let removeButton = NSButton(title: "–", target: self, action: #selector(removeProfile))
        let listButtonsRow = NSStackView(views: [addButton, removeButton, NSView()])
        listButtonsRow.orientation = .horizontal
        listButtonsRow.spacing = 4

        let leftStack = NSStackView(views: [scrollView, listButtonsRow])
        leftStack.orientation = .vertical
        leftStack.spacing = 6

        for field in [nameField, ipField, subnetField, routerField, dnsField] {
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalToConstant: 260).isActive = true
        }
        ipField.placeholderString = "192.168.1.50"
        subnetField.placeholderString = "255.255.255.0"
        routerField.placeholderString = "192.168.1.1"
        dnsField.placeholderString = "8.8.8.8, 1.1.1.1"
        modeControl.target = self
        modeControl.action = #selector(modeChanged)

        let form = NSStackView(views: [
            labeledRow("Name", nameField),
            labeledRow("Mode", modeControl),
            labeledRow("IP Address", ipField),
            labeledRow("Subnet Mask", subnetField),
            labeledRow("Router", routerField),
            labeledRow("DNS Servers", dnsField)
        ])
        form.orientation = .vertical
        form.spacing = 10
        form.alignment = .leading

        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveProfile))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"

        let importButton = NSButton(title: "Import…", target: self, action: #selector(importProfiles))
        let exportButton = NSButton(title: "Export…", target: self, action: #selector(exportProfiles))
        let bottomRow = NSStackView(views: [importButton, exportButton, NSView(), saveButton])
        bottomRow.orientation = .horizontal
        bottomRow.spacing = 8

        let rightStack = NSStackView(views: [form, NSView(), bottomRow])
        rightStack.orientation = .vertical
        rightStack.spacing = 16
        rightStack.alignment = .leading

        let mainStack = NSStackView(views: [leftStack, rightStack])
        mainStack.orientation = .horizontal
        mainStack.spacing = 20
        mainStack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            mainStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            mainStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    private func labeledRow(_ label: String, _ field: NSView) -> NSStackView {
        let labelView = NSTextField(labelWithString: label)
        labelView.alignment = .right
        labelView.translatesAutoresizingMaskIntoConstraints = false
        labelView.widthAnchor.constraint(equalToConstant: 90).isActive = true

        let row = NSStackView(views: [labelView, field])
        row.orientation = .horizontal
        row.spacing = 8
        return row
    }

    // MARK: - Data flow

    private func reloadProfiles(selecting id: UUID? = nil) {
        profiles = ProfileStore.shared.profiles
        tableView.reloadData()

        let targetID = id ?? selectedProfileID ?? profiles.first?.id
        if let targetID, let index = profiles.firstIndex(where: { $0.id == targetID }) {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
        loadSelectedProfileIntoForm()
    }

    private func loadSelectedProfileIntoForm() {
        let row = tableView.selectedRow
        guard row >= 0, row < profiles.count else {
            selectedProfileID = nil
            clearForm()
            return
        }

        let profile = profiles[row]
        selectedProfileID = profile.id
        nameField.stringValue = profile.name
        modeControl.selectedSegment = profile.mode == .dhcp ? 0 : 1
        ipField.stringValue = profile.ipAddress
        subnetField.stringValue = profile.subnetMask
        routerField.stringValue = profile.router
        dnsField.stringValue = profile.dnsServers.joined(separator: ", ")
        updateFieldAvailability()
    }

    private func clearForm() {
        nameField.stringValue = ""
        modeControl.selectedSegment = 0
        ipField.stringValue = ""
        subnetField.stringValue = ""
        routerField.stringValue = ""
        dnsField.stringValue = ""
        updateFieldAvailability()
    }

    private func updateFieldAvailability() {
        let isManual = modeControl.selectedSegment == 1
        ipField.isEnabled = isManual
        subnetField.isEnabled = isManual
        routerField.isEnabled = isManual
    }

    // MARK: - Actions

    @objc private func addProfile() {
        let profile = NetworkProfile(name: "New Profile", mode: .dhcp)
        ProfileStore.shared.addOrUpdate(profile)
        reloadProfiles(selecting: profile.id)
    }

    @objc private func removeProfile() {
        guard let id = selectedProfileID, let profile = profiles.first(where: { $0.id == id }) else { return }
        ProfileStore.shared.delete(profile)
        selectedProfileID = nil
        reloadProfiles()
    }

    @objc private func modeChanged() {
        updateFieldAvailability()
    }

    @objc private func saveProfile() {
        guard let id = selectedProfileID else { return }

        let dnsServers = dnsField.stringValue
            .split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }

        let profile = NetworkProfile(
            id: id,
            name: nameField.stringValue.isEmpty ? "Untitled Profile" : nameField.stringValue,
            mode: modeControl.selectedSegment == 0 ? .dhcp : .manual,
            ipAddress: ipField.stringValue,
            subnetMask: subnetField.stringValue,
            router: routerField.stringValue,
            dnsServers: dnsServers
        )
        ProfileStore.shared.addOrUpdate(profile)
        reloadProfiles(selecting: id)
    }

    @objc private func importProfiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try ProfileStore.shared.importProfiles(from: url)
            reloadProfiles()
        } catch {
            presentError(title: "Import Failed", message: error.localizedDescription)
        }
    }

    @objc private func exportProfiles() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "profiles.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try ProfileStore.shared.exportProfiles(to: url)
        } catch {
            presentError(title: "Export Failed", message: error.localizedDescription)
        }
    }

    private func presentError(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.runModal()
    }
}

// MARK: - NSTableViewDataSource / NSTableViewDelegate

extension ProfilesWindowController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        profiles.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("ProfileCell")
        let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField)
            ?? NSTextField(labelWithString: "")
        cell.identifier = identifier
        cell.stringValue = profiles[row].name
        cell.isBezeled = false
        cell.drawsBackground = false
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        loadSelectedProfileIntoForm()
    }
}
