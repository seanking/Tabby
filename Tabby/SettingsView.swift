import SwiftUI

/// Keys for user-configurable preferences, stored in `UserDefaults` via
/// `@AppStorage`. Keep these in one place so the settings UI and the switcher
/// read the same values.
enum SettingsKey {
    static let showAppName = "showAppName"
    static let showWindowPreview = "showWindowPreview"
    static let previewDwell = "previewDwell"

    /// Default dwell (seconds) before the window preview appears. Shared so the
    /// settings UI and the switcher agree when no value has been stored yet.
    static let defaultPreviewDwell = 1.0
}

/// The Tabby preferences window. Kept intentionally small — one section per
/// group of related options.
struct SettingsView: View {
    @AppStorage(SettingsKey.showAppName) private var showAppName = true
    @AppStorage(SettingsKey.showWindowPreview) private var showWindowPreview = true
    @AppStorage(SettingsKey.previewDwell) private var previewDwell = SettingsKey.defaultPreviewDwell
    @StateObject private var launchAtLogin = LaunchAtLogin()

    var body: some View {
        Form {
            Section("Appearance") {
                Toggle("Show app name", isOn: $showAppName)
            }

            Section("Window preview") {
                Toggle("Show window preview", isOn: $showWindowPreview)

                if showWindowPreview {
                    LabeledContent("Show after") {
                        HStack(spacing: 6) {
                            TextField("", value: $previewDwell, formatter: Self.dwellFormatter)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 60)
                            Text("seconds")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
            }
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 280)
    }

    /// Formats and validates the dwell text field: one/two-decimal seconds,
    /// clamped to a sane range so an out-of-bounds entry can't break the delay.
    private static let dwellFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimum = 0.1
        formatter.maximum = 10.0
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}

#Preview {
    SettingsView()
}
