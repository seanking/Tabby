import AppKit
import Testing
@testable import Tabby

/// Covers the menu-bar and Dock menu builders (`populateStatusMenu`,
/// `populateDockMenu`, `appendWindowGroupItems`) and the menu-bar app list
/// setting, which defaults to on.
@MainActor
@Suite("Menu bar and Dock menus")
struct StatusMenuTests {
    private func window(_ id: CGWindowID, pid: pid_t, owner: String, title: String? = nil) -> WindowInfo {
        WindowInfo(id: id, pid: pid, ownerName: owner, title: title ?? "Window \(id)", bounds: .zero)
    }

    private var sampleGroups: [DockMenuGroup] {
        dockMenuGroups(for: [
            window(1, pid: 10, owner: "Safari"),
            window(2, pid: 20, owner: "Mail"),
            window(3, pid: 10, owner: "Safari"),
        ])
    }

    /// Titles of a menu's items, with separators shown as "---".
    private func titles(of menu: NSMenu) -> [String] {
        menu.items.map { $0.isSeparatorItem ? "---" : $0.title }
    }

    private func noIcon(_ pid: pid_t) -> NSImage? { nil }

    // MARK: - Setting

    /// A throwaway defaults domain so tests don't touch the real preferences.
    private func makeDefaults() -> UserDefaults {
        let suite = "StatusMenuTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func appListIsOnByDefault() {
        #expect(SettingsKey.defaultShowMenuBarWindows)
        #expect(AppDelegate.isMenuBarWindowListEnabled(in: makeDefaults()))
    }

    @Test(arguments: [true, false])
    func appListFollowsStoredSetting(_ stored: Bool) {
        // Given
        let defaults = makeDefaults()
        defaults.set(stored, forKey: SettingsKey.showMenuBarWindows)

        // When / Then
        #expect(AppDelegate.isMenuBarWindowListEnabled(in: defaults) == stored)
    }

    // MARK: - Menu bar menu

    @Test func statusMenuListsAppsBetweenOpenAndSettings() {
        // Given
        let menu = NSMenu()

        // When
        populateStatusMenu(menu, groups: sampleGroups, showWindows: true, target: nil, icon: noIcon)

        // Then
        #expect(titles(of: menu) == ["Open Tabby", "---", "Mail", "Safari", "---", "Settings…", "---", "Quit Tabby"])
    }

    @Test func statusMenuHidesAppsWhenTurnedOff() {
        // Given
        let menu = NSMenu()

        // When
        populateStatusMenu(menu, groups: sampleGroups, showWindows: false, target: nil, icon: noIcon)

        // Then
        #expect(titles(of: menu) == ["Open Tabby", "---", "Settings…", "---", "Quit Tabby"])
    }

    @Test func statusMenuWithNoWindowsHasNoDoubleSeparator() {
        // Given
        let menu = NSMenu()

        // When
        populateStatusMenu(menu, groups: [], showWindows: true, target: nil, icon: noIcon)

        // Then
        #expect(titles(of: menu) == ["Open Tabby", "---", "Settings…", "---", "Quit Tabby"])
    }

    @Test func statusMenuReplacesItemsOnEachRebuild() {
        // Given: the menu was filled once with the app list shown.
        let menu = NSMenu()
        populateStatusMenu(menu, groups: sampleGroups, showWindows: true, target: nil, icon: noIcon)

        // When: it's rebuilt after the setting is turned off.
        populateStatusMenu(menu, groups: sampleGroups, showWindows: false, target: nil, icon: noIcon)

        // Then: no stale or duplicated items remain.
        #expect(titles(of: menu) == ["Open Tabby", "---", "Settings…", "---", "Quit Tabby"])
    }

    @Test func statusMenuKeepsKeyboardShortcuts() {
        // Given
        let menu = NSMenu()

        // When
        populateStatusMenu(menu, groups: [], showWindows: true, target: nil, icon: noIcon)

        // Then
        let settings = menu.items.first { $0.title == "Settings…" }
        let quit = menu.items.first { $0.title == "Quit Tabby" }
        #expect(settings?.keyEquivalent == ",")
        #expect(quit?.keyEquivalent == "q")
        #expect(quit?.action == #selector(NSApplication.terminate(_:)))
    }

    @Test func statusMenuItemsRouteToTarget() {
        // Given
        let menu = NSMenu()
        let target = NSObject()

        // When
        populateStatusMenu(menu, groups: sampleGroups, showWindows: true, target: target, icon: noIcon)

        // Then
        let open = menu.items.first { $0.title == "Open Tabby" }
        let settings = menu.items.first { $0.title == "Settings…" }
        #expect(open?.target === target)
        #expect(open?.action == #selector(AppDelegate.openSwitcherFromMenu(_:)))
        #expect(settings?.target === target)
        #expect(settings?.action == #selector(AppDelegate.openSettingsFromMenu(_:)))
    }

    // MARK: - App/window submenus

    @Test func appRowsHaveWindowSubmenus() throws {
        // Given
        let menu = NSMenu()
        let target = NSObject()

        // When
        let added = appendWindowGroupItems(to: menu, groups: sampleGroups, target: target, icon: noIcon)

        // Then
        #expect(added)
        let safari = try #require(menu.items.first { $0.title == "Safari" }?.submenu)
        #expect(titles(of: safari) == ["Window 1", "Window 3"])
        for item in safari.items {
            #expect(item.target === target)
            #expect(item.action == #selector(AppDelegate.activateMenuWindow(_:)))
        }
        #expect((safari.items.first?.representedObject as? WindowInfo)?.id == 1)
    }

    @Test func appRowsUseIconForTheirProcess() {
        // Given
        let menu = NSMenu()
        let safariIcon = NSImage(size: NSSize(width: 16, height: 16))
        var requestedPIDs: [pid_t] = []

        // When
        appendWindowGroupItems(to: menu, groups: sampleGroups, target: nil) { pid in
            requestedPIDs.append(pid)
            return pid == 10 ? safariIcon : nil
        }

        // Then
        #expect(requestedPIDs.sorted() == [10, 20])
        #expect(menu.items.first { $0.title == "Safari" }?.image === safariIcon)
        #expect(menu.items.first { $0.title == "Mail" }?.image == nil)
    }

    @Test func emptyGroupsAddNothing() {
        // Given
        let menu = NSMenu()

        // When
        let added = appendWindowGroupItems(to: menu, groups: [], target: nil, icon: noIcon)

        // Then
        #expect(!added)
        #expect(menu.items.isEmpty)
    }

    // MARK: - Dock menu

    @Test func dockMenuListsAppsThenSettings() {
        // Given
        let menu = NSMenu()

        // When
        populateDockMenu(menu, groups: sampleGroups, target: nil, icon: noIcon)

        // Then
        #expect(titles(of: menu) == ["Mail", "Safari", "---", "Settings…"])
    }

    @Test func dockMenuWithNoWindowsShowsOnlySettings() {
        // Given
        let menu = NSMenu()

        // When
        populateDockMenu(menu, groups: [], target: nil, icon: noIcon)

        // Then
        #expect(titles(of: menu) == ["Settings…"])
    }
}
