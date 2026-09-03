import Foundation
import ServiceManagement

/// Wraps `SMAppService.mainApp` (macOS 13+) so the settings UI can toggle
/// whether Tabby launches automatically at login. The system is the source of
/// truth: `isEnabled` is derived from the service's current status.
@MainActor
final class LaunchAtLogin: ObservableObject {
    @Published private(set) var isEnabled: Bool

    init() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    /// Registers or unregisters the app as a login item to match `enabled`,
    /// then refreshes `isEnabled` from the resulting system status so the UI
    /// reflects what actually happened (e.g. if the user must approve it).
    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            NSLog("Tabby: failed to update launch-at-login: \(error)")
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}
