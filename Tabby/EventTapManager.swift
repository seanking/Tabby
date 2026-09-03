import Carbon.HIToolbox
import Cocoa

/// Installs a global CGEventTap to detect and swallow Cmd+Tab / Cmd+Shift+Tab
/// before the system's own app switcher sees them, and to notice when Cmd is
/// released so the switcher can commit its selection. Requires Accessibility
/// access (Permissions.isAccessibilityTrusted).
final class EventTapManager {
    var onActivate: (() -> Void)?
    var onAdvance: ((_ reverse: Bool) -> Void)?
    var onCommandReleased: (() -> Void)?
    /// Fired when the user explicitly confirms the current selection with
    /// Return/Enter (as opposed to committing by releasing Cmd).
    var onSelect: (() -> Void)?
    var onEscape: (() -> Void)?
    var onHideSelected: (() -> Void)?
    var onQuitSelected: (() -> Void)?
    var onMinimizeSelected: (() -> Void)?
    /// Fired when the user presses "P" while switching to show/hide the preview.
    var onTogglePreview: (() -> Void)?

    private(set) var isSwitcherActive = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func start() {
        guard eventTap == nil else { return }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, refcon in
                guard let refcon else { return Unmanaged.passRetained(event) }
                let manager = Unmanaged<EventTapManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handle(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("Tabby: failed to create event tap — check Accessibility permission")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isSwitcherActive = false
    }

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        if type == .flagsChanged {
            if isSwitcherActive, !event.flags.contains(.maskCommand) {
                isSwitcherActive = false
                onCommandReleased?()
            }
            return Unmanaged.passRetained(event)
        }

        if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = event.flags

            if flags.contains(.maskCommand), keyCode == kVK_Tab {
                let reverse = flags.contains(.maskShift)
                if isSwitcherActive {
                    onAdvance?(reverse)
                } else {
                    isSwitcherActive = true
                    onActivate?()
                }
                return nil // swallow — prevents the system app switcher from also firing
            }

            if isSwitcherActive, keyCode == kVK_Escape {
                isSwitcherActive = false
                onEscape?()
                return nil
            }

            // Return/Enter explicitly commits the current selection so it works
            // even when the user has let go of Cmd and is navigating with the
            // arrow keys. Swallowed so it doesn't leak to the app behind the HUD.
            if isSwitcherActive, keyCode == kVK_Return || keyCode == kVK_ANSI_KeypadEnter {
                isSwitcherActive = false
                onSelect?()
                return nil
            }

            // Arrow keys traverse the (vertical) list: Down/Right → next,
            // Up/Left → previous. Swallowed so they don't reach other apps.
            if isSwitcherActive {
                switch Int(keyCode) {
                case kVK_DownArrow, kVK_RightArrow:
                    onAdvance?(false)
                    return nil
                case kVK_UpArrow, kVK_LeftArrow:
                    onAdvance?(true)
                    return nil
                case kVK_ANSI_P:
                    onTogglePreview?()
                    return nil
                default:
                    break
                }
            }

            // While switching, Cmd+H / Cmd+Q act on the *selected* window's app
            // rather than the frontmost one; swallow so they don't also fire on
            // whatever app is currently active. Cmd stays held, so the switcher
            // remains open.
            if isSwitcherActive, flags.contains(.maskCommand) {
                if keyCode == kVK_ANSI_H {
                    onHideSelected?()
                    return nil
                }
                if keyCode == kVK_ANSI_Q {
                    onQuitSelected?()
                    return nil
                }
                if keyCode == kVK_ANSI_M {
                    onMinimizeSelected?()
                    return nil
                }
            }
        }

        return Unmanaged.passRetained(event)
    }

    deinit {
        stop()
    }
}
