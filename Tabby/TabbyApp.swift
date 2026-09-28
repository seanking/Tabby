import SwiftUI

@main
struct TabbyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Tabby is a menu-bar-only (LSUIElement) background switcher with no
        // primary window. The menu-bar item is an `NSStatusItem` owned by
        // `AppDelegate` (so its window list is rebuilt each time it opens), and
        // `AppDelegate` also owns the Settings window (the SwiftUI `Settings`
        // scene can't be opened imperatively for an accessory app). This empty
        // `Settings` scene exists only to carry the app's menu commands.
        Settings {
            EmptyView()
        }
        .commands {
            // Bind ⌘, in the app's main menu so it works whenever Tabby is the
            // active app (e.g. its Settings or welcome window is focused). The
            // ⌘, that fires while the switcher HUD is up is handled separately by
            // the global event tap.
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    appDelegate.openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
