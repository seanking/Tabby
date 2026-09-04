import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private let switcher = SwitcherController()
    private var permissionPollTimer: Timer?
    private var settingsWindow: NSWindow?
    private var welcomeWindow: NSWindow?

    /// Whether the first-launch welcome/permissions window has been dismissed.
    /// Persisted so onboarding only appears the first time Tabby runs.
    private static let welcomeCompletedKey = "didCompleteWelcome"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // When the app is only acting as the unit-test host, skip all runtime
        // side effects: no status-bar item, no Accessibility permission prompt,
        // and no global event tap.
        guard !AppDelegate.isRunningTests else { return }

        setUpStatusItem()
        presentWelcomeIfNeeded()
        beginPermissionGate()
    }

    /// True when the process was launched to host `xctest` (unit tests), rather
    /// than as the real menu-bar app.
    private static var isRunningTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    func applicationWillTerminate(_ notification: Notification) {
        switcher.stop()
        permissionPollTimer?.invalidate()
    }

    // MARK: - Status item

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "square.stack",
            accessibilityDescription: "Tabby"
        )

        let menu = NSMenu()
        menu.addItem(withTitle: "Tabby", action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Tabby", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func openSettings() {
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
        // Clear any first responder AppKit assigned while becoming key, so no
        // field shows a focus ring / cursor until the user clicks into one.
        settingsWindow?.makeFirstResponder(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
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
