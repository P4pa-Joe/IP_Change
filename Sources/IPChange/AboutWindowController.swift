import AppKit

/// The "About" window: app icon, name, version/build info, Swift version,
/// and author contact details — a custom replacement for the standard
/// macOS About panel, which has no room for author/contact fields.
final class AboutWindowController: NSWindowController {

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About IP Change"
        window.center()
        window.isReleasedWhenClosed = false

        self.init(window: window)
        buildUI()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - UI construction

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let iconView = NSImageView(image: NSApp.applicationIconImage ?? NSImage())
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 64).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 64).isActive = true

        let nameLabel = NSTextField(labelWithString: appName)
        nameLabel.font = .boldSystemFont(ofSize: 16)

        let versionLabel = NSTextField(labelWithString: "Version \(appVersion) (Build on \(buildDate))")
        versionLabel.font = .systemFont(ofSize: 11)
        versionLabel.textColor = .secondaryLabelColor

        let swiftLabel = NSTextField(labelWithString: "Based on Swift \(swiftVersion)")
        swiftLabel.font = .systemFont(ofSize: 11)
        swiftLabel.textColor = .secondaryLabelColor

        let authorLabel = NSTextField(labelWithString: "Author: Sébastien Pavageau")
        let mailRow = contactRow(
            prefix: "Mail:",
            linkTitle: "seb.pav@wanadoo.fr",
            url: URL(string: "mailto:seb.pav@wanadoo.fr")!
        )
        let websiteRow = contactRow(
            prefix: "Website:",
            linkTitle: "https://audioupdater.net",
            url: URL(string: "https://audioupdater.net")!
        )

        let stack = NSStackView(views: [
            iconView, nameLabel, versionLabel, swiftLabel,
            spacer(height: 8), authorLabel, mailRow, websiteRow
        ])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    private func spacer(height: CGFloat) -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }

    /// A plain "<prefix>" label followed by a clickable link — only the
    /// link portion (the address/URL itself) is hyperlinked.
    private func contactRow(prefix: String, linkTitle: String, url: URL) -> NSStackView {
        let prefixLabel = NSTextField(labelWithString: prefix)

        let attributed = NSMutableAttributedString(string: linkTitle)
        attributed.addAttribute(.link, value: url, range: NSRange(location: 0, length: linkTitle.utf16.count))
        let linkField = NSTextField(labelWithString: "")
        linkField.attributedStringValue = attributed
        linkField.isSelectable = true
        linkField.allowsEditingTextAttributes = true

        let row = NSStackView(views: [prefixLabel, linkField])
        row.orientation = .horizontal
        row.spacing = 4
        return row
    }

    // MARK: - Bundle info

    private var appName: String {
        (Bundle.main.infoDictionary?["CFBundleName"] as? String) ?? "IP Change"
    }

    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
    }

    private var buildDate: String {
        (Bundle.main.infoDictionary?["IPChangeBuildDate"] as? String) ?? "unknown"
    }

    private var swiftVersion: String {
        (Bundle.main.infoDictionary?["IPChangeSwiftVersion"] as? String) ?? "unknown"
    }
}
