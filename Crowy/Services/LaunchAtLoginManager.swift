import Foundation
import ServiceManagement

/// Thin wrapper around `SMAppService.mainApp` that mirrors the registration
/// state into `Preferences.launchAtLogin`.
@MainActor
enum LaunchAtLoginManager {

    /// True when the main app is currently registered as a login item.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Toggles login-item registration. Returns true on success; on failure the
    /// caller should revert any optimistic UI state.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled {
                    try service.register()
                }
            } else {
                if service.status == .enabled {
                    try service.unregister()
                }
            }
            return true
        } catch {
            NSLog("LaunchAtLoginManager: \(enabled ? "register" : "unregister") failed: \(error)")
            return false
        }
    }

    /// Reconciles the persisted preference with the actual SMAppService state at launch.
    /// If the user toggled the setting off-app (e.g. via System Settings), we trust SMAppService.
    static func syncPreference(_ preferences: Preferences) {
        let actual = isEnabled
        if preferences.launchAtLogin != actual {
            preferences.launchAtLogin = actual
        }
    }
}
