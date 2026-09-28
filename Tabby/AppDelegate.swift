import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private let switcher = SwitcherController()
    private let windowManager = WindowManager()
    private var permissionPollTimer: Timer?
    private var welcomeWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem?

    /// Whether the first-launch welcome/permissions window has been dismissed.
    /// Persisted so onboarding only appears the first time Tabby runs.
    private static let welcomeCompletedKey = "didCompleteWelcome"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // When the app is only acting as the unit-test host, skip all runtime
        // side effects: no Accessibility permission prompt, no global event tap,
        // and no menu-bar item.
        guard !AppDelegate.isRunningTests else { return }

        Self.applyDockIconVisibility()
        Self.applyAppearance()
        installStatusItem()

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

    /// Right-clicking the Dock icon lists every switchable window, grouped by
    /// app: one row (icon + app name) per app, whose submenu holds that app's
    /// windows. The Dock asks for this menu each time it opens, so the list is
    /// always current. Picking a window raises it just like the switcher. A
    /// Settings item follows the window list.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        populateDockMenu(
            menu,
            groups: dockMenuGroups(for: windowManager.listWindows()),
            target: self,
            icon: menuIcon(for:)
        )
        return menu
    }

    @objc func activateMenuWindow(_ sender: NSMenuItem) {
        guard let window = sender.representedObject as? WindowInfo else { return }
        windowManager.activate(window)
    }

    @objc func openSettingsFromMenu(_ sender: NSMenuItem) {
        openSettings()
    }

    // MARK: - Menu bar item

    /// Adds Tabby's menu-bar item. Owned here as an `NSStatusItem` rather than a
    /// SwiftUI `MenuBarExtra` so its menu can be rebuilt every time it opens (see
    /// `menuNeedsUpdate(_:)`), keeping the window list current.
    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "square.stack", accessibilityDescription: "Tabby")

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    /// Rebuilds the menu-bar menu just before it opens: Open Tabby, then (when
    /// enabled in Settings → General → Menu Bar) every switchable window grouped
    /// by app, then Settings and Quit.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusItem?.menu else { return }
        // Skip enumerating windows entirely when the list is turned off.
        let showWindows = Self.isMenuBarWindowListEnabled()
        populateStatusMenu(
            menu,
            groups: showWindows ? dockMenuGroups(for: windowManager.listWindows()) : [],
            showWindows: showWindows,
            target: self,
            icon: menuIcon(for:)
        )
    }

    @objc func openSwitcherFromMenu(_ sender: NSMenuItem) {
        openSwitcher()
    }

    /// Whether Settings → General → Menu Bar's app list is on, falling back to
    /// the default (on) when the user hasn't chosen yet.
    static func isMenuBarWindowListEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: SettingsKey.showMenuBarWindows) as? Bool ?? SettingsKey.defaultShowMenuBarWindows
    }

    /// The app's icon scaled down to menu-row size.
    private func menuIcon(for pid: pid_t) -> NSImage? {
        guard let icon = windowManager.icon(for: pid)?.copy() as? NSImage else { return nil }
        icon.size = NSSize(width: 16, height: 16)
        return icon
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

    // MARK: - Appearance

    /// Applies Settings → Appearance → Theme app-wide. Setting `NSApp.appearance`
    /// restyles every window — the switcher HUD, Settings, and the welcome
    /// window — and nil lets them follow the system's light/dark setting.
    static func applyAppearance() {
        let raw = UserDefaults.standard.string(forKey: SettingsKey.appearanceMode)
        let mode = raw.flatMap(AppearanceMode.init(rawValue:)) ?? .system
        NSApp.appearance = mode.nsAppearance
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

/// One app's section in the Dock menu: its windows, alphabetized.
struct DockMenuGroup: Equatable {
    let pid: pid_t
    let appName: String
    let windows: [WindowInfo]
}

/// Groups the switcher's window list by owning app for the Dock menu. Apps are
/// sorted alphabetically by name, and each app's windows by the label the menu
/// shows, both using Finder-style ordering (case-insensitive, "Window 2" before
/// "Window 10"). Ties — e.g. two processes of the same app — fall back to pid
/// or window id so the order is stable between menu openings.
func dockMenuGroups(for windows: [WindowInfo]) -> [DockMenuGroup] {
    let windowsByPID = Dictionary(grouping: windows, by: \.pid)

    return windowsByPID
        .compactMap { pid, appWindows -> DockMenuGroup? in
            guard let first = appWindows.first else { return nil }
            let sorted = appWindows.sorted { lhs, rhs in
                let lhsName = switcherDisplayName(for: lhs, showAppName: false)
                let rhsName = switcherDisplayName(for: rhs, showAppName: false)
                switch lhsName.localizedStandardCompare(rhsName) {
                case .orderedAscending: return true
                case .orderedDescending: return false
                case .orderedSame: return lhs.id < rhs.id
                }
            }
            return DockMenuGroup(pid: pid, appName: first.ownerName, windows: sorted)
        }
        .sorted { lhs, rhs in
            switch lhs.appName.localizedStandardCompare(rhs.appName) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return lhs.pid < rhs.pid
            }
        }
}

/// Appends one row (icon + app name) per group, each with a submenu of that
/// app's windows. Picking a window sends `activateMenuWindow(_:)` to `target`
/// with the `WindowInfo` as the item's `representedObject`. Shared by the Dock
/// and menu-bar menus. Returns whether any rows were added, so callers can
/// decide on a trailing separator.
@MainActor
@discardableResult
func appendWindowGroupItems(
    to menu: NSMenu,
    groups: [DockMenuGroup],
    target: AnyObject?,
    icon: (pid_t) -> NSImage?
) -> Bool {
    for group in groups {
        let submenu = NSMenu(title: group.appName)
        for window in group.windows {
            let item = NSMenuItem(
                title: switcherDisplayName(for: window, showAppName: false),
                action: #selector(AppDelegate.activateMenuWindow(_:)),
                keyEquivalent: ""
            )
            item.target = target
            item.representedObject = window
            submenu.addItem(item)
        }

        let appItem = NSMenuItem(title: group.appName, action: nil, keyEquivalent: "")
        appItem.image = icon(group.pid)
        appItem.submenu = submenu
        menu.addItem(appItem)
    }

    return !groups.isEmpty
}

/// Fills the Dock icon's right-click menu: the app/window list, then Settings.
@MainActor
func populateDockMenu(
    _ menu: NSMenu,
    groups: [DockMenuGroup],
    target: AnyObject?,
    icon: (pid_t) -> NSImage?
) {
    if appendWindowGroupItems(to: menu, groups: groups, target: target, icon: icon) {
        menu.addItem(.separator())
    }
    let settingsItem = NSMenuItem(
        title: "Settings…",
        action: #selector(AppDelegate.openSettingsFromMenu(_:)),
        keyEquivalent: ""
    )
    settingsItem.target = target
    menu.addItem(settingsItem)
}

/// Rebuilds the menu-bar menu in place: Open Tabby, then (when `showWindows` is
/// on) the app/window list, then Settings and Quit. Clears any existing items
/// first, since the same menu is refilled every time it opens.
@MainActor
func populateStatusMenu(
    _ menu: NSMenu,
    groups: [DockMenuGroup],
    showWindows: Bool,
    target: AnyObject?,
    icon: (pid_t) -> NSImage?
) {
    menu.removeAllItems()

    let openItem = NSMenuItem(
        title: "Open Tabby",
        action: #selector(AppDelegate.openSwitcherFromMenu(_:)),
        keyEquivalent: ""
    )
    openItem.target = target
    menu.addItem(openItem)
    menu.addItem(.separator())

    if showWindows, appendWindowGroupItems(to: menu, groups: groups, target: target, icon: icon) {
        menu.addItem(.separator())
    }

    let settingsItem = NSMenuItem(
        title: "Settings…",
        action: #selector(AppDelegate.openSettingsFromMenu(_:)),
        keyEquivalent: ","
    )
    settingsItem.target = target
    menu.addItem(settingsItem)
    menu.addItem(.separator())

    menu.addItem(NSMenuItem(title: "Quit Tabby", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
}
