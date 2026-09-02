import SwiftUI

@main
struct TabbyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No visible window on launch — Tabby is a menu-bar-only (LSUIElement)
        // background switcher. Settings is used as an inert placeholder scene.
        Settings {
            EmptyView()
        }
    }
}
