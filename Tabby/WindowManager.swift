import AppKit
import ApplicationServices
import CoreGraphics
import ScreenCaptureKit

/// Enumerates on-screen windows across every app and can raise/focus one of
/// them by combining the CoreGraphics window list (for ordering, bounds and
/// thumbnails) with the Accessibility API (for actually focusing a specific
/// window rather than just activating an app).
final class WindowManager: Sendable {
    private let selfPID = ProcessInfo.processInfo.processIdentifier

    /// Returns on-screen, layer-0 windows in front-to-back order, which
    /// approximates most-recently-used order — the same list Windows 11's
    /// Alt+Tab shows (individual windows, not grouped by app).
    func listWindows() -> [WindowInfo] {
        // The on-screen list excludes hidden apps (their windows aren't on
        // screen), so query the full window list too and append any windows
        // that belong to a hidden app, flagged so the UI can gray them out.
        let onScreen = copyWindows(options: [.optionOnScreenOnly, .excludeDesktopElements])
        let visibleIDs = Set(onScreen.map(\.id))

        let hiddenPIDs = Set(
            NSWorkspace.shared.runningApplications
                .filter(\.isHidden)
                .map(\.processIdentifier)
        )

        let hidden = copyWindows(options: [.excludeDesktopElements])
            .filter { hiddenPIDs.contains($0.pid) && !visibleIDs.contains($0.id) }
            .map { window -> WindowInfo in
                var window = window
                window.isHidden = true
                return window
            }

        let visibleAndHidden = standardWindows(onScreen + hidden)

        // Minimized windows aren't reliably present in the CoreGraphics list, so
        // gather them from the Accessibility tree and append them (grayed out).
        let minimized = minimizedWindows(excluding: Set(visibleAndHidden.map(\.id)))

        return visibleAndHidden + minimized
    }

    /// Collects minimized standard windows straight from each regular app's
    /// Accessibility tree (`AXMinimized`), since CoreGraphics doesn't reliably
    /// list minimized windows. Skips ids already present in the CG-based list.
    private func minimizedWindows(excluding existingIDs: Set<CGWindowID>) -> [WindowInfo] {
        var result: [WindowInfo] = []

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let pid = app.processIdentifier
            guard pid != selfPID else { continue }

            for (windowID, axWindow) in axWindowsByID(for: pid) {
                // Don't require AXStandardWindow here: on current macOS minimized
                // windows misreport their subrole as AXDialog (the same quirk
                // hidden apps have), so that check would wrongly drop every
                // minimized window. AXMinimized is a sufficient signal on its own —
                // only real windows minimize to the Dock.
                guard !existingIDs.contains(windowID),
                      axBool(axWindow, kAXMinimizedAttribute as String)
                else { continue }

                result.append(WindowInfo(
                    id: windowID,
                    pid: pid,
                    ownerName: app.localizedName ?? "",
                    title: axString(axWindow, kAXTitleAttribute as String) ?? "",
                    bounds: .zero,
                    isHidden: app.isHidden,
                    isMinimized: true
                ))
            }
        }
        return result
    }

    private func copyWindows(options: CGWindowListOption) -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: AnyObject]] else {
            return []
        }

        var result: [WindowInfo] = []
        for entry in list {
            guard
                let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
                let pid = entry[kCGWindowOwnerPID as String] as? pid_t, pid != selfPID,
                let ownerName = entry[kCGWindowOwnerName as String] as? String,
                let windowID = entry[kCGWindowNumber as String] as? CGWindowID,
                let boundsDict = entry[kCGWindowBounds as String] as? [String: CGFloat]
            else { continue }

            let bounds = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )

            // Filter out menu-bar extras, tooltips, and other tiny helper windows.
            guard bounds.width > 60, bounds.height > 60 else { continue }
            guard ownerName != "Dock", ownerName != "Window Server" else { continue }

            let title = (entry[kCGWindowName as String] as? String) ?? ""
            result.append(WindowInfo(id: windowID, pid: pid, ownerName: ownerName, title: title, bounds: bounds))
        }
        return result
    }

    /// Filters the CG window list down to real, user-facing windows and fills in
    /// missing titles, both using the app's Accessibility windows.
    ///
    /// Apps like Mail expose extra layer-0 helper/panel windows that pass the
    /// size filter; we drop any window that doesn't match a standard window
    /// (`AXStandardWindow`) in the app's AX tree. If an app exposes no AX windows
    /// at all (can't verify), its windows are kept as-is. AX windows are cached
    /// per app so each process is only queried once.
    private func standardWindows(_ windows: [WindowInfo]) -> [WindowInfo] {
        var axByPID: [pid_t: [CGWindowID: AXUIElement]] = [:]

        return windows.compactMap { window -> WindowInfo? in
            let axWindows: [CGWindowID: AXUIElement]
            if let cached = axByPID[window.pid] {
                axWindows = cached
            } else {
                axWindows = axWindowsByID(for: window.pid)
                axByPID[window.pid] = axWindows
            }

            // Can't verify without AX windows — keep the CG window untouched.
            guard !axWindows.isEmpty else { return window }

            // Map each CG window to its *exact* AX window (frames can be
            // identical, e.g. two maximized Safari windows, so we can't match by
            // frame). Windows with no AX element are helper/panel surfaces.
            guard let axWindow = axWindows[window.id] else { return nil }

            let subrole = axString(axWindow, kAXSubroleAttribute as String)
            let axTitle = axString(axWindow, kAXTitleAttribute as String) ?? ""
            let effectiveTitle = window.title.isEmpty ? axTitle : window.title

            if window.isHidden {
                // Hidden apps (⌘H) misreport subroles (real windows come back as
                // AXDialog), so don't require AXStandardWindow. But still drop
                // obvious non-windows: AXUnknown surfaces and untitled helper
                // windows (e.g. the transparent/shadow windows Electron/Tauri
                // apps like cmux expose), which would otherwise appear as extra,
                // blank rows.
                if subrole == "AXUnknown" { return nil }
                if subrole != (kAXStandardWindowSubrole as String), effectiveTitle.isEmpty {
                    return nil
                }
            } else if !isStandardWindow(axWindow) {
                // Visible app: require a standard window to drop helper/panels.
                return nil
            }

            guard window.title.isEmpty, !axTitle.isEmpty else { return window }
            let title = axTitle

            return WindowInfo(
                id: window.id,
                pid: window.pid,
                ownerName: window.ownerName,
                title: title,
                bounds: window.bounds,
                isHidden: window.isHidden
            )
        }
    }

    /// Builds a precise `CGWindowID -> AXUIElement` map for an app's windows via
    /// the private `_AXUIElementGetWindow`, which returns the CoreGraphics window
    /// id backing an AX element. This is the only reliable way to pair a CG
    /// window with its AX window when frames are ambiguous.
    private func axWindowsByID(for pid: pid_t) -> [CGWindowID: AXUIElement] {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let axWindows = windowsRef as? [AXUIElement]
        else { return [:] }

        var map: [CGWindowID: AXUIElement] = [:]
        for axWindow in axWindows {
            var windowID: CGWindowID = 0
            if _AXUIElementGetWindow(axWindow, &windowID) == .success, windowID != 0 {
                map[windowID] = axWindow
            }
        }
        return map
    }

    private func isStandardWindow(_ axWindow: AXUIElement) -> Bool {
        // Missing subrole info: don't over-filter.
        guard let subrole = axString(axWindow, kAXSubroleAttribute as String) else { return true }
        return subrole == (kAXStandardWindowSubrole as String)
    }

    func icon(for pid: pid_t) -> NSImage? {
        NSRunningApplication(processIdentifier: pid)?.icon
    }

    /// Hides the app owning the given pid (equivalent to the app receiving ⌘H).
    func hide(pid: pid_t) {
        NSRunningApplication(processIdentifier: pid)?.hide()
    }

    /// Requests a graceful quit of the app owning the given pid (⌘Q). The app
    /// may prompt (e.g. for unsaved changes) before actually terminating.
    func quit(pid: pid_t) {
        NSRunningApplication(processIdentifier: pid)?.terminate()
    }

    /// Minimizes a single window (⌘M) by setting its Accessibility minimized
    /// attribute, located by its exact CoreGraphics window id.
    func minimize(_ window: WindowInfo) {
        guard let axWindow = axWindowsByID(for: window.pid)[window.id] else { return }
        AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
    }

    /// Reads the notification badge labels (e.g. "3", "99+") that the Dock
    /// displays on app icons. There's no public API to read another app's badge
    /// directly, so we walk the Dock's Accessibility tree and read each app
    /// tile's `AXStatusLabel`. Returns a map of Dock item (app) name to badge.
    func notificationBadges() -> [String: String] {
        guard let dockPID = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock")
            .first?.processIdentifier
        else { return [:] }

        let dock = AXUIElementCreateApplication(dockPID)
        guard let dockChildren = axChildren(of: dock) else { return [:] }

        var badges: [String: String] = [:]
        for list in dockChildren where axString(list, kAXRoleAttribute as String) == (kAXListRole as String) {
            for item in axChildren(of: list) ?? [] {
                guard
                    let name = axString(item, kAXTitleAttribute as String),
                    let badge = axString(item, "AXStatusLabel"),
                    Self.isBadgeCount(badge)
                else { continue }
                badges[name] = badge
            }
        }
        return badges
    }

    /// Whether a Dock tile's status label is an actual notification count
    /// ("3", "99+") rather than other text a tile can transiently expose (e.g. a
    /// date), which we don't want to render as a badge. Pure and internal so it
    /// can be unit-tested.
    static func isBadgeCount(_ label: String) -> Bool {
        let digits = label.hasSuffix("+") ? label.dropLast() : Substring(label)
        return !digits.isEmpty && digits.allSatisfy(\.isNumber)
    }

    private func axChildren(of element: AXUIElement) -> [AXUIElement]? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &ref) == .success else {
            return nil
        }
        return ref as? [AXUIElement]
    }

    private func axString(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else {
            return nil
        }
        return ref as? String
    }

    private func axBool(_ element: AXUIElement, _ attribute: String) -> Bool {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else {
            return false
        }
        return (ref as? Bool) ?? false
    }

    /// Captures a live snapshot of a single window for the switcher HUD via
    /// ScreenCaptureKit (the modern replacement for the deprecated
    /// `CGWindowListCreateImage`). Requires Screen Recording access and macOS 14+;
    /// returns nil (so the UI falls back to the app icon) without it or if the
    /// window can't be captured (e.g. it's minimized/off-screen).
    func thumbnail(for window: WindowInfo) async -> NSImage? {
        guard #available(macOS 14.0, *) else { return nil }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            guard let scWindow = content.windows.first(where: { $0.windowID == window.id }) else {
                return nil
            }

            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            let config = SCStreamConfiguration()
            // Capture at 2x the window's point size for a crisp preview on
            // Retina displays, while keeping the image a reasonable size.
            let scale = 2
            config.width = max(Int(scWindow.frame.width) * scale, 1)
            config.height = max(Int(scWindow.frame.height) * scale, 1)
            config.showsCursor = false
            config.ignoreShadowsSingleWindow = true

            let cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
            return NSImage(cgImage: cgImage, size: NSSize(width: scWindow.frame.width, height: scWindow.frame.height))
        } catch {
            return nil
        }
    }

    /// Activates the window's owning app and raises/focuses that specific
    /// window, found by its exact CoreGraphics window id via the AX map.
    func activate(_ window: WindowInfo) {
        let app = NSRunningApplication(processIdentifier: window.pid)
        // A hidden app (⌘H) won't show its windows on activate alone — unhide
        // first so the raised window actually becomes visible. No-op otherwise.
        app?.unhide()
        app?.activate(options: [.activateIgnoringOtherApps])

        guard let axWindow = axWindowsByID(for: window.pid)[window.id] else { return }
        // Restore the window if it was minimized, then raise/focus it.
        AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(axWindow, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }
}

/// Returns the CoreGraphics window id backing an Accessibility element. This is
/// a private, undocumented AppKit symbol (the same one AltTab and similar window
/// switchers rely on) — there is no public API that maps an `AXUIElement` to a
/// `CGWindowID`. Only used to pair windows we already enumerate; if Apple ever
/// removes it, `axWindowsByID(for:)` simply returns an empty map and windows
/// fall back to their unfiltered CoreGraphics info.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError
