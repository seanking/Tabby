import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let switcher = SwitcherController()
    private var permissionPollTimer: Timer?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // When the app is only acting as the unit-test host, skip all runtime
        // side effects: no status-bar item, no Accessibility permission prompt,
        // and no global event tap.
        guard !AppDelegate.isRunningTests else { return }

        setUpStatusItem()
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

        let accessibilityItem = NSMenuItem(
            title: "Grant Accessibility Access…",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)

        let screenRecordingItem = NSMenuItem(
            title: "Grant Screen Recording Access…",
            action: #selector(openScreenRecordingSettings),
            keyEquivalent: ""
        )
        screenRecordingItem.target = self
        menu.addItem(screenRecordingItem)

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

    @objc private func openAccessibilitySettings() {
        Permissions.openAccessibilitySettings()
    }

    @objc private func openScreenRecordingSettings() {
        Permissions.openScreenRecordingSettings()
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            let window = NSWindow(contentViewController: hosting)
            window.title = "Tabby Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }

        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Permission gate

    /// Cmd+Tab interception and window raising both require Accessibility
    /// access. Prompt once, then poll until granted (the user has to leave
    /// the app to flip the switch in System Settings) before starting the tap.
    private func beginPermissionGate() {
        if Permissions.isAccessibilityTrusted(prompt: true) {
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
