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
    /// Window whose large preview is shown after the user dwells on it. Nil until
    /// the dwell delay elapses without the selection changing.
    @Published private(set) var previewWindowID: CGWindowID?

    /// Last successful window snapshot per window id, kept across Cmd+Tab
    /// invocations. Lets hidden/minimized windows — which can't be captured live —
    /// show their most recent on-screen image instead of just an icon. Pruned to
    /// the current window list on each activation to bound memory.
    private var thumbnailCache: [CGWindowID: NSImage] = [:]

    private let eventTap = EventTapManager()
    private let windowManager = WindowManager()
    private var panel: SwitcherPanel?
    private var thumbnailTask: Task<Void, Never>?

    /// Pending timer that reveals the HUD if Cmd is still held after the delay.
    private var presentationTask: Task<Void, Never>?
    /// Whether the HUD is currently on screen (vs. an in-flight quick switch).
    private var isPanelPresented = false

    /// How long the first Cmd+Tab waits before showing the HUD. Releasing Cmd
    /// within this window just switches to the next window — like the system
    /// switcher — while holding Cmd past it reveals the full list.
    private static let activationDelay: TimeInterval = 0.4

    /// Fires the dwell preview if the selection is held long enough.
    private var dwellTask: Task<Void, Never>?

    /// Whether the window preview is enabled (Settings → Window preview).
    private var previewEnabled: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.showWindowPreview) as? Bool ?? true
    }

    /// How long the user must dwell on a selection (Cmd held, no movement)
    /// before its preview appears, from Settings.
    private var previewDwell: TimeInterval {
        UserDefaults.standard.object(forKey: SettingsKey.previewDwell) as? Double ?? SettingsKey.defaultPreviewDwell
    }

    func start() {
        eventTap.onActivate = { [weak self] in self?.activate() }
        eventTap.onAdvance = { [weak self] reverse in self?.advance(reverse: reverse) }
        eventTap.onCommandReleased = { [weak self] in self?.commit() }
        eventTap.onSelect = { [weak self] in self?.commit() }
        eventTap.onEscape = { [weak self] in self?.cancel() }
        eventTap.onHideSelected = { [weak self] in self?.hideSelected() }
        eventTap.onQuitSelected = { [weak self] in self?.quitSelected() }
        eventTap.onMinimizeSelected = { [weak self] in self?.minimizeSelected() }
        eventTap.onTogglePreview = { [weak self] in self?.togglePreview() }
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

        // Drop cache entries for windows that no longer exist, then seed the
        // visible thumbnails from the cache so hidden/minimized windows show
        // their last snapshot right away. Live captures refresh these below.
        let ids = Set(list.map(\.id))
        thumbnailCache = thumbnailCache.filter { ids.contains($0.key) }
        thumbnails = thumbnailCache

        selectedIndex = 1 // land on the next-most-recent window, like the system switcher

        // Don't show the HUD yet: a quick Cmd+Tab (Cmd released before the
        // delay) should just switch to the next window. Only reveal the list if
        // Cmd is still held once the timer fires.
        schedulePresentation()
    }

    /// Starts the delay after which the HUD appears if the user keeps holding
    /// Cmd. Cancelled if Cmd is released (quick switch) or the switch ends.
    private func schedulePresentation() {
        presentationTask?.cancel()
        presentationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.activationDelay))
            guard !Task.isCancelled else { return }
            self?.presentPanel()
        }
    }

    /// Reveals the HUD now, cancelling the pending delay. No-op if already shown
    /// or if the switch was cancelled/committed in the meantime.
    private func presentPanel() {
        presentationTask?.cancel()
        presentationTask = nil
        guard !isPanelPresented, !windows.isEmpty else { return }
        isPanelPresented = true
        showPanel()
        // Only capture window snapshots when the preview feature is enabled.
        if previewEnabled {
            loadThumbnails()
        }
        // Start the dwell timer for the initial selection so simply holding Cmd
        // on the default window eventually reveals its preview.
        scheduleDwellPreview()
    }

    /// (Re)starts the dwell timer for the current selection, hiding any preview
    /// that was showing. If the same selection is held for `previewDwell` seconds
    /// (Cmd still down), the selected window's large preview appears.
    private func scheduleDwellPreview() {
        dwellTask?.cancel()
        if previewWindowID != nil {
            previewWindowID = nil
            resizePanelKeepingLeftEdge()
        }
        guard isPanelPresented, previewEnabled else { return }
        dwellTask = Task { [weak self, dwell = previewDwell] in
            try? await Task.sleep(for: .seconds(dwell))
            guard !Task.isCancelled else { return }
            self?.showDwellPreview()
        }
    }

    private func showDwellPreview() {
        guard isPanelPresented, windows.indices.contains(selectedIndex) else { return }
        previewWindowID = windows[selectedIndex].id
        resizePanelKeepingLeftEdge()
    }

    /// Pressing "P" while switching shows the preview immediately (skipping the
    /// dwell) or hides it if already showing.
    private func togglePreview() {
        guard isPanelPresented, previewEnabled else { return }
        dwellTask?.cancel()
        if previewWindowID != nil {
            previewWindowID = nil
            resizePanelKeepingLeftEdge()
        } else {
            showDwellPreview()
        }
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
        // A second Tab (or arrow key) means the user wants to browse: reveal the
        // HUD immediately rather than waiting out the delay.
        presentPanel()
        selectedIndex = Self.nextIndex(from: selectedIndex, reverse: reverse, count: windows.count)
        // Moving the selection restarts the dwell timer and hides any preview.
        scheduleDwellPreview()
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
        presentPanel()
        let pid = windows[selectedIndex].pid
        windowManager.hide(pid: pid)
        windows = Self.markingHidden(pid: pid, in: windows)
    }

    /// ⌘Q while switching: quit the selected window's app and drop all of its
    /// windows from the list, keeping the selection valid.
    private func quitSelected() {
        guard windows.indices.contains(selectedIndex) else { return }
        presentPanel()
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
        presentPanel()
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
        endPresentation()
        if windows.indices.contains(selectedIndex) {
            windowManager.activate(windows[selectedIndex])
        }
        windows = []
    }

    private func cancel() {
        endPresentation()
        windows = []
    }

    /// Tears down any pending timer and hides the HUD, returning to idle. Safe
    /// whether or not the HUD was ever shown (quick switch vs. browsed).
    private func endPresentation() {
        presentationTask?.cancel()
        presentationTask = nil
        dwellTask?.cancel()
        dwellTask = nil
        previewWindowID = nil
        isPanelPresented = false
        hidePanel()
    }

    private func loadThumbnails() {
        thumbnailTask?.cancel()
        let snapshot = windows
        let manager = windowManager
        thumbnailTask = Task.detached(priority: .userInitiated) {
            for window in snapshot {
                if Task.isCancelled { return }
                if let image = await manager.thumbnail(for: window) {
                    await MainActor.run { [weak self] in
                        self?.thumbnails[window.id] = image
                        // Remember this snapshot so the window can still show a
                        // preview later when it's hidden/minimized and can't be
                        // captured live.
                        self?.thumbnailCache[window.id] = image
                        // If this window's preview is already showing (e.g. "P"
                        // was pressed before its snapshot finished), re-fit now.
                        if self?.previewWindowID == window.id {
                            self?.resizePanelKeepingLeftEdge()
                        }
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

    /// Re-fits the panel when the preview appears/disappears without moving the
    /// existing list: the panel's top-left corner stays pinned so it only grows
    /// or shrinks downward (the inline preview expands under the selected row),
    /// animated so it eases open rather than the whole HUD jumping.
    private func resizePanelKeepingLeftEdge() {
        guard let panel else { return }
        Task { @MainActor in
            guard let contentView = panel.contentViewController?.view else { return }
            contentView.layoutSubtreeIfNeeded()
            let size = contentView.fittingSize

            // AppKit frames are bottom-left based; pin the top-left corner so the
            // list stays anchored and only the right edge (and, if needed, the
            // bottom) moves.
            let current = panel.frame
            let newFrame = NSRect(
                x: current.minX,
                y: current.maxY - size.height,
                width: size.width,
                height: size.height
            )
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(newFrame, display: true)
            }
            panel.invalidateShadow()
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
