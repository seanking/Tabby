# Tabby

Tabby is a macOS menu-bar app that replaces the system's ⌘Tab app switcher with a
window switcher: instead of jumping between apps, ⌘Tab in Tabby steps through
every open *window*, with live thumbnails, filtering, and quick window actions
built in.

Tabby runs as a background (menu-bar-only) app — no Dock icon or main window
required, though both are optional via Settings.

## Features

- **Window-level switching** — ⌘Tab cycles through individual windows, not just
  apps, grouped and ordered like the system switcher.
- **Quick switch or full HUD** — a fast ⌘Tab-and-release just switches to the
  previous window; holding ⌘ past a short delay reveals the full switcher list.
- **Live previews** — hold on a selection (or press `P`) to see a large preview
  of the window, rendered from a live screen capture when available.
- **Filtering** — press ⌘F (or click the filter bar) to narrow the list by app
  or window title.
- **In-switcher window actions** — hide (⌘H), minimize (⌘M), or quit (⌘Q) the
  selected window's app without leaving the switcher.
- **Dock and menu bar integration** — right-click the Dock icon or open the
  menu-bar item for a live, app-grouped list of every open window.
- **Notification badges** — app badge counts (e.g. unread counts) are mirrored
  onto each app's icon in the switcher.
- **Configurable appearance** — theme (system/light/dark), size, icon
  animations, and preview size/delay, all in Settings.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘Tab / ⌘⇧Tab | Activate switcher / advance forward or backward |
| ←/→ or ↑/↓ | Move the selection |
| Return | Commit the selection |
| Esc | Cancel |
| ⌘F | Show the filter bar |
| P | Toggle the window preview |
| ⌘H | Hide the selected window's app |
| ⌘M | Minimize the selected window |
| ⌘Q | Quit the selected window's app |
| ⌘, | Open Settings |

## Permissions

Tabby needs **Accessibility** access to intercept ⌘Tab globally and to raise
the window you pick — the app won't switch windows without it. **Screen
Recording** access is optional and only used to render live window previews;
everything else works without it. Both are requested from the first-launch
welcome window or from Settings → Permissions.

## Requirements

- macOS 26 or later
- Xcode 26 or later (Swift 6)

## Building and running

Open `Tabby.xcodeproj` in Xcode and run the **Tabby** scheme. The app launches
as a menu-bar item (look for the stacked-squares icon); a first-run window
walks through granting permissions.

A separate **Tabby-Dev** build configuration is available for day-to-day
debugging — it uses its own bundle ID (`dev.seanking.Tabby.dev`) so it can run
side by side with a release build without colliding in Accessibility/Screen
Recording permission lists.

### Tests

Run the `TabbyTests` target (`⌘U` in Xcode) to execute the unit test suite,
which covers the pure logic behind the switcher: key-event decisions, list
transforms, navigation, badge/display-name formatting, and preview sizing.

## Project structure

| File | Responsibility |
| --- | --- |
| `TabbyApp.swift` | App entry point; carries menu commands for an accessory app |
| `AppDelegate.swift` | Lifecycle, menu-bar item, Dock menu, onboarding, permission gate |
| `EventTapManager.swift` | Global `CGEventTap` that intercepts ⌘Tab and switcher hotkeys |
| `SwitcherController.swift` | Core switching state machine driving the HUD and preview |
| `SwitcherPanel.swift` / `SwitcherView.swift` | The switcher HUD window and its SwiftUI content |
| `PreviewCard.swift` | The floating window-preview card shown beside the HUD |
| `WindowManager.swift` / `WindowInfo.swift` | Enumerates, activates, and captures thumbnails of on-screen windows |
| `Permissions.swift` | Accessibility / Screen Recording permission checks and prompts |
| `SettingsView.swift` | Settings window (General, Appearance, Permissions tabs) |
| `LaunchAtLogin.swift` | "Launch at login" toggle backed by `SMAppService` |
