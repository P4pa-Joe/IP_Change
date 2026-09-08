import AppKit

/// The "Preferences" window: login item, success-notification toggle, and
/// the rollback verification delay used by ProfileApplier.
final class PreferencesWindowController: NSWindowController {

    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at Login", target: nil, action: nil)
    private let showSuccessNotificationsCheckbox = NSButton(
        checkboxWithTitle: "Show a notification when a profile is applied successfully",
        target: nil,
        action: nil
    )
    private let rollbackDelayField = NSTextField()
    private let rollbackDelayStepper = NSStepper()

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 220),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Preferences"
        window.center()
        window.isReleasedWhenClosed = false

        self.init(window: window)
        buildUI()
        loadValues()
    }

    func show() {
        loadValues()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - UI construction

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(launchAtLoginToggled)
        if !LoginItemManager.isSupported {
            launchAtLoginCheckbox.isEnabled = false
            launchAtLoginCheckbox.toolTip = "Only available when running the built IP Change.app, not via swift run."
        }

        showSuccessNotificationsCheckbox.target = self
        showSuccessNotificationsCheckbox.action = #selector(showSuccessNotificationsToggled)

        rollbackDelayField.translatesAutoresizingMaskIntoConstraints = false
        rollbackDelayField.widthAnchor.constraint(equalToConstant: 50).isActive = true
        rollbackDelayField.target = self
        rollbackDelayField.action = #selector(rollbackDelayFieldChanged)

        rollbackDelayStepper.minValue = 2
        rollbackDelayStepper.maxValue = 60
        rollbackDelayStepper.increment = 1
        rollbackDelayStepper.target = self
        rollbackDelayStepper.action = #selector(rollbackDelayStepperChanged)

        let rollbackLabel = NSTextField(labelWithString: "Verify reachability for")
        let rollbackSuffix = NSTextField(labelWithString: "seconds after applying a profile")
        let rollbackRow = NSStackView(views: [rollbackLabel, rollbackDelayField, rollbackDelayStepper, rollbackSuffix])
        rollbackRow.orientation = .horizontal
        rollbackRow.spacing = 6

        let rollbackExplanation = NSTextField(wrappingLabelWithString:
            "The previous configuration is restored automatically if the interface becomes unreachable.")
        rollbackExplanation.textColor = .secondaryLabelColor
        rollbackExplanation.font = .systemFont(ofSize: 11)

        let contentWidth: CGFloat = 420

        let stack = NSStackView(views: [
            launchAtLoginCheckbox,
            showSuccessNotificationsCheckbox,
            rollbackRow,
            rollbackExplanation
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            rollbackExplanation.widthAnchor.constraint(equalToConstant: contentWidth)
        ])
    }

    // MARK: - Data flow

    private func loadValues() {
        launchAtLoginCheckbox.state = (LoginItemManager.isSupported && LoginItemManager.isEnabled) ? .on : .off
        showSuccessNotificationsCheckbox.state = AppPreferences.shared.showSuccessNotifications ? .on : .off

        let delay = AppPreferences.shared.rollbackVerificationDelay
        rollbackDelayField.stringValue = String(Int(delay))
        rollbackDelayStepper.doubleValue = delay
    }

    // MARK: - Actions

    @objc private func launchAtLoginToggled() {
        do {
            try LoginItemManager.setEnabled(launchAtLoginCheckbox.state == .on)
        } catch {
            presentError(
                title: "Could Not Update Login Item",
                message: error.localizedDescription
            )
            launchAtLoginCheckbox.state = LoginItemManager.isEnabled ? .on : .off
        }
    }

    @objc private func showSuccessNotificationsToggled() {
        AppPreferences.shared.showSuccessNotifications = showSuccessNotificationsCheckbox.state == .on
    }

    @objc private func rollbackDelayFieldChanged() {
        let value = max(rollbackDelayStepper.minValue, min(rollbackDelayStepper.maxValue, rollbackDelayField.doubleValue))
        applyRollbackDelay(value)
    }

    @objc private func rollbackDelayStepperChanged() {
        applyRollbackDelay(rollbackDelayStepper.doubleValue)
    }

    private func applyRollbackDelay(_ value: Double) {
        AppPreferences.shared.rollbackVerificationDelay = value
        rollbackDelayField.stringValue = String(Int(value))
        rollbackDelayStepper.doubleValue = value
    }

    private func presentError(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.runModal()
    }
}
