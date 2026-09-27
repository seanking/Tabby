import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let switcher = SwitcherController()
    private var permissionPollTimer: Timer?
    private var welcomeWindow: NSWindow?
    private var settingsWindow: NSWindow?

    /// Whether the first-launch welcome/permissions window has been dismissed.
    /// Persisted so onboarding only appears the first time Tabby runs.
    private static let welcomeCompletedKey = "didCompleteWelcome"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // When the app is only acting as the unit-test host, skip all runtime
        // side effects: no Accessibility permission prompt and no global event
        // tap. (The menu-bar item is a SwiftUI `MenuBarExtra` scene gated on the
        // same flag.)
        guard !AppDelegate.isRunningTests else { return }

        Self.applyDockIconVisibility()

        // Opening Settings from the switcher HUD (⌘, while it's up) routes back
        // here so the same window logic serves the menu bar, ⌘,, and the HUD.
        switcher.onOpenSettings = { [weak self] in self?.openSettings() }

        presentWelcomeIfNeeded()
        beginPermissionGate()
    }

    // MARK: - Settings window

    /// Opens (or re-fronts) the preferences window. Owned here rather than via a
    /// SwiftUI `Settings` scene because that scene can't be opened imperatively:
    /// macOS refuses the old `showSettingsWindow:` selector, and `SettingsLink`
    /// won't bring an accessory app's window to the foreground. Activating and
    /// ordering front here makes the window reliably appear on top from every
    /// entry point — the menu bar, ⌘,, and the switcher HUD.
    func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: makeSettingsTabController())
            window.title = "Tabby Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            // Don't let a text field grab focus when the window opens, so the
            // switcher size/delay fields start unfocused.
            window.initialFirstResponder = nil
            settingsWindow = window
        }

        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        // Force the window above other apps' windows even if activation is
        // deferred by the system (accessory apps aren't always granted it).
        settingsWindow?.orderFrontRegardless()
        // Clear any first responder AppKit assigned while becoming key, so no
        // field shows a focus ring / cursor until the user clicks into one.
        settingsWindow?.makeFirstResponder(nil)
    }

    /// True when the process was launched to host `xctest` (unit tests), rather
    /// than as the real menu-bar app.
    static var isRunningTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    func applicationWillTerminate(_ notification: Notification) {
        switcher.stop()
        permissionPollTimer?.invalidate()
    }

    /// Opens the switcher HUD on demand, for the menu bar's "Open Tabby" item.
    func openSwitcher() {
        switcher.openFromMenu()
    }

    // MARK: - Dock icon

    /// Clicking the Dock icon (or relaunching Tabby while it's running) opens
    /// the switcher instead of the default reopen behavior.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !AppDelegate.isRunningTests else { return false }
        openSwitcher()
        return false
    }

    /// Shows or hides the Dock icon to match Settings → General → Dock. The
    /// Info.plist declares `LSUIElement`, so Tabby starts as an accessory app;
    /// switching to `.regular` at runtime adds the Dock icon.
    static func applyDockIconVisibility() {
        let show = UserDefaults.standard.object(forKey: SettingsKey.showDockIcon) as? Bool ?? SettingsKey.defaultShowDockIcon
        let policy: NSApplication.ActivationPolicy = show ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)

        // Dropping to `.accessory` deactivates the app, which would push the
        // Settings window (where the toggle lives) behind other apps. Bring it
        // back once the policy change settles.
        if policy == .accessory {
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    // MARK: - First-launch onboarding

    /// On the very first launch, show a window explaining the permissions Tabby
    /// needs (and why) with buttons to grant them. Subsequent launches skip it;
    /// the same controls remain available in Settings → Permissions.
    private func presentWelcomeIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.welcomeCompletedKey) else { return }

        let hosting = NSHostingController(rootView: WelcomeView(onDone: { [weak self] in
            self?.welcomeWindow?.close()
        }))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Welcome to Tabby"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        welcomeWindow = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Mark onboarding complete once the welcome window is dismissed — whether via
    /// its button or the close box — so it won't reappear on the next launch.
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === welcomeWindow else { return }
        UserDefaults.standard.set(true, forKey: Self.welcomeCompletedKey)
        welcomeWindow = nil
    }

    // MARK: - Permission gate

    /// Cmd+Tab interception and window raising both require Accessibility
    /// access. Check quietly (without prompting) and poll until granted — the
    /// system prompt is only shown when the user explicitly chooses "Grant
    /// Accessibility Access…" from the menu, so it doesn't reappear on every
    /// run (each debug build is a fresh, untrusted binary).
    private func beginPermissionGate() {
        if Permissions.isAccessibilityTrusted(prompt: false) {
            switcher.start()
            return
        }

        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard Permissions.isAccessibilityTrusted(prompt: false) else { return }
            timer.invalidate()
            Task { @MainActor in
                self?.permissionPollTimer = nil
                self?.switcher.start()
            }
        }
    }
}
