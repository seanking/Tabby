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
    /// Fired when the user presses Cmd+, while switching, to open Settings.
    var onOpenSettings: (() -> Void)?
    /// Fired when the user presses Cmd+F while switching to reveal the filter.
    var onFilterActivate: (() -> Void)?
    /// Fired for each character typed into the filter (already the resolved,
    /// modifier-applied string, e.g. "a").
    var onFilterInput: ((_ text: String) -> Void)?
    /// Fired when Delete/Backspace is pressed while filtering.
    var onFilterBackspace: (() -> Void)?

    private(set) var isSwitcherActive = false
    /// Whether the filter field is active. Once true, releasing Cmd no longer
    /// commits — the filter owns dismissal (Esc cancels, Return selects).
    private(set) var isFiltering = false
    /// Whether the user has started browsing with the arrow keys. Like filtering,
    /// this latches the HUD open so releasing Cmd no longer commits — the user
    /// picks explicitly with Return (or cancels with Esc). Cmd+Tab does not latch,
    /// so the classic hold-Cmd / release-to-commit quick switch is unaffected.
    private(set) var isLatched = false

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

    /// Forces the tap into an active, latched session — used when the switcher is
    /// opened by something other than Cmd+Tab (the menu bar's "Open Tabby"). With
    /// no Cmd held to release, the session must latch so arrow keys navigate and
    /// the user dismisses explicitly with Return/Esc (or a click) rather than by
    /// releasing Cmd.
    func beginLatchedSession() {
        isSwitcherActive = true
        isFiltering = false
        isLatched = true
    }

    /// Clears all in-session state so the next Cmd+Tab starts clean. Called by
    /// the controller whenever a switch ends, covering exits the tap doesn't
    /// observe as a keystroke (e.g. quitting the last window of a filtered app,
    /// which dismisses the HUD from the controller rather than via Return/Esc).
    func endSession() {
        isSwitcherActive = false
        isFiltering = false
        isLatched = false
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
        isFiltering = false
        isLatched = false
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
                // Once filtering or arrow-browsing has begun, releasing Cmd keeps
                // the list on screen — the user dismisses explicitly with Return
                // or Esc rather than by letting go of Cmd.
                if isFiltering || isLatched { return Unmanaged.passRetained(event) }
                isSwitcherActive = false
                // Committing raises/focuses a window via synchronous AX calls;
                // run it a tick later so this tap callback returns immediately
                // (see `dispatch` for why).
                DispatchQueue.main.async { [weak self] in self?.onCommandReleased?() }
            }
            return Unmanaged.passRetained(event)
        }

        if type == .keyDown {
            let flags = event.flags
            let decision = Self.decideKeyDown(
                keyCode: Int(event.getIntegerValueField(.keyboardEventKeycode)),
                command: flags.contains(.maskCommand),
                shift: flags.contains(.maskShift),
                isSwitcherActive: isSwitcherActive,
                isFiltering: isFiltering,
                isLatched: isLatched,
                characters: NSEvent(cgEvent: event)?.characters
            )

            isSwitcherActive = decision.isSwitcherActive
            isFiltering = decision.isFiltering
            isLatched = decision.isLatched

            // Run the action a tick later so this callback returns immediately
            // (see `dispatch`). The session-state fields above are updated
            // synchronously, so the next event still decodes against fresh state.
            dispatch(decision.action)

            // Swallowed keys (return nil) don't reach the app behind the HUD nor
            // the system's own Cmd+Tab switcher.
            return decision.swallow ? nil : Unmanaged.passRetained(event)
        }

        return Unmanaged.passRetained(event)
    }

    /// Routes a decoded action to its callback on the main queue, one run-loop
    /// tick after the tap callback returns. The switcher work behind these
    /// callbacks (enumerating windows, reading the Dock and every app's
    /// Accessibility tree, raising a window) is slow, synchronous cross-process
    /// IPC. Running it inline would keep the tap callback busy long enough for
    /// macOS to hit the event-tap timeout and disable the tap — which leaks the
    /// in-flight Cmd+Tab (and any that follow until re-enable) straight to the
    /// system's own switcher. Deferring keeps the callback near-instant. The
    /// callbacks already run on the main actor and the main queue is FIFO, so
    /// this preserves ordering across events.
    private func dispatch(_ action: KeyDecision.Action) {
        guard action != .none else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch action {
            case .none: break
            case .activate: onActivate?()
            case .advance(let reverse): onAdvance?(reverse)
            case .select: onSelect?()
            case .escape: onEscape?()
            case .openSettings: onOpenSettings?()
            case .hideSelected: onHideSelected?()
            case .quitSelected: onQuitSelected?()
            case .minimizeSelected: onMinimizeSelected?()
            case .togglePreview: onTogglePreview?()
            case .filterActivate: onFilterActivate?()
            case .filterInput(let text): onFilterInput?(text)
            case .filterBackspace: onFilterBackspace?()
            }
        }
    }

    /// The result of interpreting a keyDown while the switcher may be active:
    /// which callback to fire, whether to swallow the event, and the resulting
    /// active state. Pure and separated from `CGEvent` so it can be unit-tested.
    struct KeyDecision: Equatable {
        enum Action: Equatable {
            case none
            case activate
            case advance(reverse: Bool)
            case select
            case escape
            case openSettings
            case hideSelected
            case quitSelected
            case minimizeSelected
            case togglePreview
            case filterActivate
            case filterInput(String)
            case filterBackspace
        }

        var action: Action
        var swallow: Bool
        var isSwitcherActive: Bool
        /// Whether the filter remains active after this key. Defaults to false so
        /// call sites (and tests) that predate the filter stay unchanged.
        var isFiltering: Bool
        /// Whether arrow-browsing has latched the HUD open, so releasing Cmd no
        /// longer commits. Defaults to false to keep older call sites unchanged.
        var isLatched: Bool

        init(
            action: Action,
            swallow: Bool,
            isSwitcherActive: Bool,
            isFiltering: Bool = false,
            isLatched: Bool = false
        ) {
            self.action = action
            self.swallow = swallow
            self.isSwitcherActive = isSwitcherActive
            self.isFiltering = isFiltering
            self.isLatched = isLatched
        }
    }

    /// Maps a keyDown (keycode + Cmd/Shift state + current active state) to the
    /// switcher action, mirroring the routing the live event tap performs:
    ///
    /// - Cmd+Tab activates (or, if already switching, advances — Shift reverses),
    ///   always swallowed so the system switcher never fires.
    /// - While switching: Esc cancels, Return/Enter commits, the arrow keys
    ///   advance/retreat, "P" toggles the preview, and Cmd+H/Q/M act on the
    ///   selected window — all swallowed. Everything else passes through.
    /// - Cmd+F opens the filter. Once filtering, printable keys build the query,
    ///   Delete removes a character, the up/down arrows still navigate, and every
    ///   key is swallowed so nothing leaks to the app behind the HUD. The "P"
    ///   preview shortcut and the left/right arrows step aside so those letters
    ///   can be typed instead.
    /// - Pressing any arrow key latches the HUD open (`isLatched`) so releasing
    ///   Cmd no longer commits; Cmd+Tab deliberately does not, preserving the
    ///   classic hold-and-release quick switch. Other in-switcher keys carry the
    ///   latched state forward unchanged.
    static func decideKeyDown(
        keyCode: Int,
        command: Bool,
        shift: Bool,
        isSwitcherActive: Bool,
        isFiltering: Bool = false,
        isLatched: Bool = false,
        characters: String? = nil
    ) -> KeyDecision {
        if command, keyCode == kVK_Tab {
            // Advancing within a live session carries the current filter/latch
            // state forward. Starting a *fresh* switch must not: a new session
            // begins unfiltered and unlatched, so stale flags from a prior
            // session can't linger and swallow this session's Cmd-release commit.
            guard isSwitcherActive else {
                return KeyDecision(action: .activate, swallow: true, isSwitcherActive: true)
            }
            return KeyDecision(action: .advance(reverse: shift), swallow: true, isSwitcherActive: true, isFiltering: isFiltering, isLatched: isLatched)
        }

        // Only Cmd+Tab is intercepted when the switcher isn't open.
        guard isSwitcherActive else {
            return KeyDecision(action: .none, swallow: false, isSwitcherActive: false)
        }

        // Cmd+, opens Settings and dismisses the HUD — the switcher is Tabby's
        // main surface, so its settings shortcut works even while it's showing.
        if command, keyCode == kVK_ANSI_Comma {
            return KeyDecision(action: .openSettings, swallow: true, isSwitcherActive: false)
        }

        // Cmd+F reveals the filter; a repeat while filtering is a no-op (but is
        // still swallowed so it never types an "f").
        if command, keyCode == kVK_ANSI_F {
            return KeyDecision(
                action: isFiltering ? .none : .filterActivate,
                swallow: true,
                isSwitcherActive: true,
                isFiltering: true,
                isLatched: isLatched
            )
        }

        switch keyCode {
        case kVK_Escape:
            return KeyDecision(action: .escape, swallow: true, isSwitcherActive: false)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            return KeyDecision(action: .select, swallow: true, isSwitcherActive: false)
        case kVK_DownArrow:
            return KeyDecision(action: .advance(reverse: false), swallow: true, isSwitcherActive: true, isFiltering: isFiltering, isLatched: true)
        case kVK_UpArrow:
            return KeyDecision(action: .advance(reverse: true), swallow: true, isSwitcherActive: true, isFiltering: isFiltering, isLatched: true)
        default:
            break
        }

        // Left/right arrows and the "P" preview toggle only apply outside the
        // filter, where their letters aren't wanted as query text.
        if !isFiltering {
            switch keyCode {
            case kVK_RightArrow:
                return KeyDecision(action: .advance(reverse: false), swallow: true, isSwitcherActive: true, isLatched: true)
            case kVK_LeftArrow:
                return KeyDecision(action: .advance(reverse: true), swallow: true, isSwitcherActive: true, isLatched: true)
            case kVK_ANSI_P:
                return KeyDecision(action: .togglePreview, swallow: true, isSwitcherActive: true, isLatched: isLatched)
            default:
                break
            }
        }

        if command {
            switch keyCode {
            case kVK_ANSI_H:
                return KeyDecision(action: .hideSelected, swallow: true, isSwitcherActive: true, isFiltering: isFiltering, isLatched: isLatched)
            case kVK_ANSI_Q:
                return KeyDecision(action: .quitSelected, swallow: true, isSwitcherActive: true, isFiltering: isFiltering, isLatched: isLatched)
            case kVK_ANSI_M:
                return KeyDecision(action: .minimizeSelected, swallow: true, isSwitcherActive: true, isFiltering: isFiltering, isLatched: isLatched)
            default:
                break
            }
        }

        // Filter text entry: Delete edits, printable keys extend the query, and
        // anything else is swallowed so it can't reach the app underneath.
        if isFiltering {
            if keyCode == kVK_Delete {
                return KeyDecision(action: .filterBackspace, swallow: true, isSwitcherActive: true, isFiltering: true, isLatched: isLatched)
            }
            if !command, let characters, isPrintable(characters) {
                return KeyDecision(action: .filterInput(characters), swallow: true, isSwitcherActive: true, isFiltering: true, isLatched: isLatched)
            }
            return KeyDecision(action: .none, swallow: true, isSwitcherActive: true, isFiltering: true, isLatched: isLatched)
        }

        return KeyDecision(action: .none, swallow: false, isSwitcherActive: true, isLatched: isLatched)
    }

    /// Whether a resolved key string is ordinary text to append to the filter
    /// (letters, digits, space, punctuation) rather than a control character.
    private static func isPrintable(_ text: String) -> Bool {
        guard let scalar = text.unicodeScalars.first else { return false }
        return scalar.value >= 0x20 && scalar.value != 0x7F
    }

    deinit {
        stop()
    }
}
