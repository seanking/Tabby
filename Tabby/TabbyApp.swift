import SwiftUI

@main
struct TabbyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Tabby is a menu-bar-only (LSUIElement) background switcher with no
        // primary window. The menu-bar item is a SwiftUI `MenuBarExtra`; its
        // items route to `AppDelegate`, which owns the Settings window (the
        // SwiftUI `Settings` scene can't be opened imperatively for an accessory
        // app). Skipped under the unit-test host to avoid side effects.
        MenuBarExtra(
            "Tabby",
            systemImage: "square.stack",
            isInserted: .constant(!AppDelegate.isRunningTests)
        ) {
            Button("Open Tabby") {
                appDelegate.openSwitcher()
            }

            Divider()

            Button("Settings…") {
                appDelegate.openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("Quit Tabby") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
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
