import Foundation

/// User-configurable app settings, persisted via UserDefaults.
final class AppPreferences {

    static let shared = AppPreferences()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let showSuccessNotifications = "showSuccessNotifications"
        static let rollbackVerificationDelay = "rollbackVerificationDelay"
    }

    static let defaultRollbackVerificationDelay: TimeInterval = 6

    private init() {
        defaults.register(defaults: [
            Keys.showSuccessNotifications: true,
            Keys.rollbackVerificationDelay: Self.defaultRollbackVerificationDelay
        ])
    }

    /// Whether to show a banner when a profile is applied successfully.
    /// Errors and rollbacks are always surfaced regardless of this setting.
    var showSuccessNotifications: Bool {
        get { defaults.bool(forKey: Keys.showSuccessNotifications) }
        set { defaults.set(newValue, forKey: Keys.showSuccessNotifications) }
    }

    /// How long to wait after applying a profile before checking whether
    /// the interface is still reachable and rolling back if not.
    var rollbackVerificationDelay: TimeInterval {
        get { defaults.double(forKey: Keys.rollbackVerificationDelay) }
        set { defaults.set(newValue, forKey: Keys.rollbackVerificationDelay) }
    }
}
