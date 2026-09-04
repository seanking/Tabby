import AppKit
import SwiftUI

/// Keys for user-configurable preferences, stored in `UserDefaults` via
/// `@AppStorage`. Keep these in one place so the settings UI and the switcher
/// read the same values.
enum SettingsKey {
    static let showAppName = "showAppName"
    static let showBadges = "showBadges"
    static let showWindowPreview = "showWindowPreview"
    static let previewDwell = "previewDwell"
    static let activationDelay = "activationDelay"
    static let fontSize = "fontSize"
    static let badgeSize = "badgeSize"

    /// Default dwell (seconds) before the window preview appears. Shared so the
    /// settings UI and the switcher agree when no value has been stored yet.
    static let defaultPreviewDwell = 1.0

    /// Default delay (seconds) before the switcher HUD appears on the first
    /// Cmd+Tab. Releasing Cmd within this window is a quick switch. Shared so the
    /// settings UI and the switcher agree when no value has been stored yet.
    static let defaultActivationDelay = 0.4

    /// Default point size for the switcher's window-name labels. Matches the
    /// system body text size the switcher used before the size was configurable.
    static let defaultFontSize = 13.0

    /// Default point size for the notification-count badges on switcher icons.
    static let defaultBadgeSize = 9.0
}

/// Builds the Tabby preferences window's content as a native AppKit toolbar tab
/// controller — the standard macOS System Settings look, with large centered
/// toolbar items and a window that resizes to fit each tab. Each tab hosts one
/// SwiftUI pane. A plain SwiftUI `TabView` can't produce this appearance inside
/// a manually-created `NSWindow`, so we drop down to `NSTabViewController` in
/// `.toolbar` mode and wrap each pane in an `NSHostingController`.
@MainActor
func makeSettingsTabController() -> NSTabViewController {
    let controller = NSTabViewController()
    controller.tabStyle = .toolbar

    func tab(_ title: String, symbol: String, _ view: some View) -> NSTabViewItem {
        // Constrain the width so the grouped Form doesn't stretch; the height is
        // left to the pane so the window sizes to each tab's content.
        let item = NSTabViewItem(viewController: NSHostingController(rootView: view.frame(width: 460)))
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }

    controller.addTabViewItem(tab("General", symbol: "gearshape", GeneralSettingsPane()))
    controller.addTabViewItem(tab("Appearance", symbol: "paintbrush", PreviewSettingsPane()))
    controller.addTabViewItem(tab("Permissions", symbol: "lock.shield", PermissionsSettingsPane()))
    return controller
}

/// First-launch onboarding. Explains the two macOS permissions Tabby relies on
/// and why, and lets the user grant them before using the switcher. Shown once
/// (see `AppDelegate`); afterwards the same controls live in Settings →
/// Permissions. Status is polled while visible so the buttons update the moment
/// the user flips a switch in System Settings.
struct WelcomeView: View {
    /// Called when the user dismisses the welcome window.
    var onDone: () -> Void

    @State private var accessibilityGranted = Permissions.isAccessibilityTrusted(prompt: false)
    @State private var screenRecordingGranted = Permissions.isScreenRecordingGranted()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to Tabby")
                    .font(.largeTitle.bold())
                Text("Tabby replaces ⌘Tab with a window switcher. It needs a couple of macOS permissions to work — you can grant them now or later from Settings.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                WelcomePermissionRow(
                    title: "Accessibility",
                    detail: "Required to intercept ⌘Tab and raise the window you pick.",
                    granted: accessibilityGranted,
                    grant: grantAccessibility,
                    openSettings: Permissions.openAccessibilitySettings
                )
                Divider()
                WelcomePermissionRow(
                    title: "Screen Recording",
                    detail: "Optional — used only for live window previews. The switcher works without it.",
                    granted: screenRecordingGranted,
                    grant: grantScreenRecording,
                    openSettings: Permissions.openScreenRecordingSettings
                )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )

            HStack {
                if !accessibilityGranted {
                    Text("Tabby will start switching as soon as Accessibility is granted.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(accessibilityGranted ? "Get Started" : "Continue", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
        .task { await pollStatus() }
    }

    private func grantAccessibility() {
        _ = Permissions.isAccessibilityTrusted(prompt: true)
        Permissions.openAccessibilitySettings()
    }

    private func grantScreenRecording() {
        Permissions.requestScreenRecording()
        Permissions.openScreenRecordingSettings()
    }

    /// Refresh the granted flags about once a second while the window is on
    /// screen so the UI reflects changes made in System Settings without a
    /// restart.
    private func pollStatus() async {
        while !Task.isCancelled {
            accessibilityGranted = Permissions.isAccessibilityTrusted(prompt: false)
            screenRecordingGranted = Permissions.isScreenRecordingGranted()
            try? await Task.sleep(for: .seconds(1))
        }
    }
}

/// A single permission row for the welcome window. Unlike `PermissionRow`, this
/// uses a plain `HStack` (not `LabeledContent`) so it lays out correctly outside
/// a grouped `Form`: the title/detail take the flexible left column and the
/// status badge plus action button keep their natural width on the right.
private struct WelcomePermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let grant: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.green)
                    .fixedSize()
                Button("Open Settings…", action: openSettings)
                    .fixedSize()
            } else {
                Button("Grant…", action: grant)
                    .fixedSize()
            }
        }
        .padding(.vertical, 8)
    }
}

/// The macOS privacy permissions Tabby depends on, each with its current state
/// and a button to grant it. Status is polled while the pane is visible so it
/// updates as soon as the user flips the switch in System Settings.
private struct PermissionsSettingsPane: View {
    @State private var accessibilityGranted = Permissions.isAccessibilityTrusted(prompt: false)
    @State private var screenRecordingGranted = Permissions.isScreenRecordingGranted()

    var body: some View {
        Form {
            Section {
                PermissionRow(
                    title: "Accessibility",
                    detail: "Required to intercept ⌘Tab and raise windows.",
                    granted: accessibilityGranted,
                    grant: grantAccessibility,
                    openSettings: Permissions.openAccessibilitySettings
                )
                PermissionRow(
                    title: "Screen Recording",
                    detail: "Needed for live window previews. Optional.",
                    granted: screenRecordingGranted,
                    grant: grantScreenRecording,
                    openSettings: Permissions.openScreenRecordingSettings
                )
            } header: {
                Text("Permissions")
            }
        }
        .formStyle(.grouped)
        .task { await pollStatus() }
    }

    private func grantAccessibility() {
        // Surface the system prompt (also registers the app in the list), then
        // take the user to the relevant Settings pane.
        _ = Permissions.isAccessibilityTrusted(prompt: true)
        Permissions.openAccessibilitySettings()
    }

    private func grantScreenRecording() {
        Permissions.requestScreenRecording()
        Permissions.openScreenRecordingSettings()
    }

    /// Refresh the granted flags about once a second while the pane is on screen
    /// so the UI reflects changes made in System Settings without a restart.
    private func pollStatus() async {
        while !Task.isCancelled {
            accessibilityGranted = Permissions.isAccessibilityTrusted(prompt: false)
            screenRecordingGranted = Permissions.isScreenRecordingGranted()
            try? await Task.sleep(for: .seconds(1))
        }
    }
}

/// A single permission row: title and description on the left; on the right a
/// status badge plus a button that links out to the System Settings pane where
/// the permission can be enabled or disabled.
private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let grant: () -> Void
    let openSettings: () -> Void

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                if granted {
                    Label("Granted", systemImage: "checkmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.green)
                    // Already granted: just link out so the user can turn it off.
                    Button("Open Settings…", action: openSettings)
                } else {
                    Label("Not granted", systemImage: "exclamationmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.secondary)
                    // Not granted: prompt and then link out to enable it.
                    Button("Grant…", action: grant)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// General options: launch behavior and switcher activation.
private struct GeneralSettingsPane: View {
    @AppStorage(SettingsKey.activationDelay) private var activationDelay = SettingsKey.defaultActivationDelay
    @StateObject private var launchAtLogin = LaunchAtLogin()

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
            }

            Section {
                LabeledContent("Show after") {
                    numericField(value: $activationDelay, range: 0...5, step: 0.1, unit: "seconds", formatter: Self.delayFormatter)
                }
            } header: {
                Text("Switcher")
            } footer: {
                Text("How long to hold ⌘ before the switcher appears. A quick ⌘Tab within this delay just switches to the previous window.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// Formats and validates the activation-delay field: seconds clamped to a
    /// sane range so an out-of-bounds entry can't leave the HUD unreachable.
    private static let delayFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimum = 0.0
        formatter.maximum = 5.0
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}

/// Switcher appearance and window-preview options: label/badge sizing plus
/// whether to show the preview and how long to dwell.
private struct PreviewSettingsPane: View {
    @AppStorage(SettingsKey.showAppName) private var showAppName = true
    @AppStorage(SettingsKey.showBadges) private var showBadges = true
    @AppStorage(SettingsKey.fontSize) private var fontSize = SettingsKey.defaultFontSize
    @AppStorage(SettingsKey.badgeSize) private var badgeSize = SettingsKey.defaultBadgeSize
    @AppStorage(SettingsKey.showWindowPreview) private var showWindowPreview = true
    @AppStorage(SettingsKey.previewDwell) private var previewDwell = SettingsKey.defaultPreviewDwell

    var body: some View {
        Form {
            Section("Appearance") {
                Toggle("Show app name", isOn: $showAppName)
                Toggle("Show badges on icons", isOn: $showBadges)

                LabeledContent("Font size") {
                    numericField(value: $fontSize, range: 11...28, step: 1, unit: "pt", formatter: Self.fontSizeFormatter)
                }

                if showBadges {
                    LabeledContent("Badge size") {
                        numericField(value: $badgeSize, range: 7...20, step: 1, unit: "pt", formatter: Self.badgeSizeFormatter)
                    }
                }
            }

            Section {
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
            } header: {
                Text("Preview")
            } footer: {
                Text("Hold ⌘ on a window to preview it after the delay, or press P while switching.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// Whole-point size formatter for the switcher name font (matches the font
    /// size stepper's range so typed values are clamped the same way).
    private static let fontSizeFormatter = pointSizeFormatter(min: 11, max: 28)

    /// Whole-point size formatter for the icon badges (matches the badge size
    /// stepper's range).
    private static let badgeSizeFormatter = pointSizeFormatter(min: 7, max: 20)

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

/// A hand-editable numeric control: a text field for typing an exact value, a
/// trailing unit label, and a stepper for nudging it — all sharing the same
/// clamped range so neither input can go out of bounds. Shared by the settings
/// panes that expose a numeric preference.
private func numericField(
    value: Binding<Double>,
    range: ClosedRange<Double>,
    step: Double,
    unit: String,
    formatter: NumberFormatter
) -> some View {
    HStack(spacing: 6) {
        TextField("", value: value, formatter: formatter)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .frame(width: 50)
        Text(unit)
            .foregroundStyle(.secondary)
        Stepper("", value: value, in: range, step: step)
            .labelsHidden()
    }
}

/// Builds a formatter that accepts a whole number of points within a range,
/// rejecting fractions and out-of-bounds entries.
private func pointSizeFormatter(min: Double, max: Double) -> NumberFormatter {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimum = NSNumber(value: min)
    formatter.maximum = NSNumber(value: max)
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 0
    formatter.allowsFloats = false
    return formatter
}

// Canvas preview only. The real window uses the native AppKit toolbar tabs built
// by `makeSettingsTabController()`; this SwiftUI `TabView` just lets the panes be
// iterated on in the Xcode preview canvas.
#Preview {
    TabView {
        GeneralSettingsPane()
            .tabItem { Label("General", systemImage: "gearshape") }
        PreviewSettingsPane()
            .tabItem { Label("Appearance", systemImage: "paintbrush") }
        PermissionsSettingsPane()
            .tabItem { Label("Permissions", systemImage: "lock.shield") }
    }
    .frame(width: 480, height: 400)
}
