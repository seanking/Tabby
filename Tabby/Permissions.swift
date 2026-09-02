import AppKit
import ApplicationServices
import CoreGraphics

enum Permissions {
    /// Checks (and optionally prompts for) Accessibility access, required to
    /// install a global event tap and to raise/focus windows via AXUIElement.
    static func isAccessibilityTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options: [String: Bool] = [key: prompt]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// Screen Recording access is only needed to render live window thumbnails.
    /// The switcher still works without it (icons only).
    static func isScreenRecordingGranted() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestScreenRecording() {
        CGRequestScreenCaptureAccess()
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    static func openScreenRecordingSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }
}
