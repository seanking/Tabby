import SwiftUI

/// Keys for user-configurable preferences, stored in `UserDefaults` via
/// `@AppStorage`. Keep these in one place so the settings UI and the switcher
/// read the same values.
enum SettingsKey {
    static let showAppName = "showAppName"
}

/// The Tabby preferences window. Kept intentionally small — one section per
/// group of related options.
struct SettingsView: View {
    @AppStorage(SettingsKey.showAppName) private var showAppName = true
    @StateObject private var launchAtLogin = LaunchAtLogin()

    var body: some View {
        Form {
            Section("Appearance") {
                Toggle("Show app name", isOn: $showAppName)
            }

            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
            }
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 220)
    }
}

#Preview {
    SettingsView()
}
