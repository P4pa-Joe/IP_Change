import Foundation
import ServiceManagement

/// Registers/unregisters IP Change as a login item via ServiceManagement.
///
/// This only works when running from a real, bundled `.app` (built with
/// `build-app.sh`) — `SMAppService.mainApp` needs the bundle identifier and
/// Info.plist that only exist there. A bare `swift run` binary has neither,
/// so `isSupported` reports that up front instead of failing confusingly
/// when the user flips the checkbox.
enum LoginItemManager {

    static var isSupported: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
