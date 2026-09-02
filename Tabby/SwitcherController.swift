import AppKit
import Combine
import SwiftUI

/// Owns the whole Cmd+Tab replacement flow: listens for the hotkey via
/// EventTapManager, snapshots the window list via WindowManager, and drives
/// the SwitcherPanel/SwitcherView HUD while Cmd is held down.
@MainActor
final class SwitcherController: ObservableObject {
    @Published private(set) var windows: [WindowInfo] = []
    @Published private(set) var selectedIndex: Int = 0
    @Published private(set) var thumbnails: [CGWindowID: NSImage] = [:]
    @Published private(set) var icons: [pid_t: NSImage] = [:]
    /// Notification badge labels (e.g. "3") keyed by app pid, read from the Dock.
    @Published private(set) var badges: [pid_t: String] = [:]

    private let eventTap = EventTapManager()
    private let windowManager = WindowManager()
    private var panel: SwitcherPanel?
    private var thumbnailTask: Task<Void, Never>?

    func start() {
        eventTap.onActivate = { [weak self] in self?.activate() }
        eventTap.onAdvance = { [weak self] reverse in self?.advance(reverse: reverse) }
        eventTap.onCommandReleased = { [weak self] in self?.commit() }
        eventTap.onEscape = { [weak self] in self?.cancel() }
        eventTap.onHideSelected = { [weak self] in self?.hideSelected() }
        eventTap.onQuitSelected = { [weak self] in self?.quitSelected() }
        eventTap.onMinimizeSelected = { [weak self] in self?.minimizeSelected() }
        eventTap.start()
    }

    func stop() {
        eventTap.stop()
    }

    private func activate() {
        let list = windowManager.listWindows()
        guard list.count > 1 else { return }

        windows = list
        icons = Dictionary(uniqueKeysWithValues: Set(list.map(\.pid)).compactMap { pid in
            windowManager.icon(for: pid).map { (pid, $0) }
        })
        badges = badgesByPID(for: list)
        thumbnails = [:]
        selectedIndex = 1 // land on the next-most-recent window, like the system switcher
        showPanel()
        loadThumbnails()
    }

    /// Maps the Dock's badge labels (keyed by app name) onto the pids present
    /// in the window list, using each running app's localized name.
    private func badgesByPID(for windows: [WindowInfo]) -> [pid_t: String] {
        let badgesByName = windowManager.notificationBadges()
        guard !badgesByName.isEmpty else { return [:] }

        return Dictionary(uniqueKeysWithValues: Set(windows.map(\.pid)).compactMap { pid -> (pid_t, String)? in
            guard
                let name = NSRunningApplication(processIdentifier: pid)?.localizedName,
                let badge = badgesByName[name]
            else { return nil }
            return (pid, badge)
        })
    }

    private func advance(reverse: Bool) {
        guard !windows.isEmpty else { return }
        selectedIndex = Self.nextIndex(from: selectedIndex, reverse: reverse, count: windows.count)
    }

    /// Computes the next selection index, wrapping around at both ends. Pure and
    /// nonisolated so it can be unit-tested without the main actor.
    nonisolated static func nextIndex(from index: Int, reverse: Bool, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (index + (reverse ? -1 : 1) + count) % count
    }

    /// ⌘H while switching: hide the selected window's app and gray out all of
    /// its rows in place (the app stays in the list).
    private func hideSelected() {
        guard windows.indices.contains(selectedIndex) else { return }
        let pid = windows[selectedIndex].pid
        windowManager.hide(pid: pid)
        windows = Self.markingHidden(pid: pid, in: windows)
    }

    /// ⌘Q while switching: quit the selected window's app and drop all of its
    /// windows from the list, keeping the selection valid.
    private func quitSelected() {
        guard windows.indices.contains(selectedIndex) else { return }
        let pid = windows[selectedIndex].pid
        windowManager.quit(pid: pid)

        let result = Self.removingApp(pid: pid, from: windows, selectedIndex: selectedIndex)
        guard result.windows.count > 1 else {
            cancel()
            return
        }

        windows = result.windows
        selectedIndex = result.selectedIndex
        resizePanelToFit()
    }

    /// ⌘M while switching: minimize the selected window and gray it out in place
    /// (it stays in the list, like a hidden app, and can be restored by
    /// selecting it).
    private func minimizeSelected() {
        guard windows.indices.contains(selectedIndex) else { return }
        let window = windows[selectedIndex]
        windowManager.minimize(window)
        windows = Self.markingMinimized(id: window.id, in: windows)
    }

    // MARK: - Pure list transformations (unit-tested)

    /// Marks every window belonging to `pid` as hidden, leaving the list order
    /// and count unchanged.
    nonisolated static func markingHidden(pid: pid_t, in windows: [WindowInfo]) -> [WindowInfo] {
        windows.map { window in
            guard window.pid == pid else { return window }
            var window = window
            window.isHidden = true
            return window
        }
    }

    /// Marks the single window with `id` as minimized.
    nonisolated static func markingMinimized(id: CGWindowID, in windows: [WindowInfo]) -> [WindowInfo] {
        windows.map { window in
            guard window.id == id else { return window }
            var window = window
            window.isMinimized = true
            return window
        }
    }

    /// Removes every window belonging to `pid` and returns the trimmed list
    /// alongside a selection index clamped to remain in range.
    nonisolated static func removingApp(
        pid: pid_t,
        from windows: [WindowInfo],
        selectedIndex: Int
    ) -> (windows: [WindowInfo], selectedIndex: Int) {
        let remaining = windows.filter { $0.pid != pid }
        let clamped = remaining.isEmpty ? 0 : min(max(selectedIndex, 0), remaining.count - 1)
        return (remaining, clamped)
    }

    private func commit() {
        hidePanel()
        if windows.indices.contains(selectedIndex) {
            windowManager.activate(windows[selectedIndex])
        }
        windows = []
    }

    private func cancel() {
        hidePanel()
        windows = []
    }

    private func loadThumbnails() {
        thumbnailTask?.cancel()
        let snapshot = windows
        let manager = windowManager
        thumbnailTask = Task.detached(priority: .userInitiated) {
            for window in snapshot {
                if Task.isCancelled { return }
                if let image = manager.thumbnail(for: window) {
                    await MainActor.run { [weak self] in
                        self?.thumbnails[window.id] = image
                    }
                }
            }
        }
    }

    private func showPanel() {
        let panel = panel ?? makePanel()
        self.panel = panel
        centerOnActiveScreen(panel)
        panel.orderFrontRegardless()
    }

    /// Re-fits the panel to its content after the window list shrinks (e.g. an
    /// app was quit). Deferred so SwiftUI applies the updated list before we
    /// measure the new fitting size.
    private func resizePanelToFit() {
        guard let panel else { return }
        Task { @MainActor in
            self.centerOnActiveScreen(panel)
        }
    }

    private func hidePanel() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> SwitcherPanel {
        let panel = SwitcherPanel()
        let hosting = NSHostingController(rootView: SwitcherView(controller: self))
        panel.contentViewController = hosting
        return panel
    }

    private func centerOnActiveScreen(_ panel: SwitcherPanel) {
        guard let contentView = panel.contentViewController?.view else { return }
        contentView.layoutSubtreeIfNeeded()
        let contentSize = contentView.fittingSize
        panel.setContentSize(contentSize)

        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let origin = NSPoint(
            x: frame.midX - contentSize.width / 2,
            y: frame.midY - contentSize.height / 2
        )
        panel.setFrameOrigin(origin)

        // Recompute the native window shadow for the new (rounded) content size,
        // otherwise it can render stale or squared off.
        panel.invalidateShadow()
    }
}
