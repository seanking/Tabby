import Carbon.HIToolbox
import Testing
@testable import Tabby

/// Covers `EventTapManager.decideKeyDown`, the pure routing behind the global
/// event tap: which key maps to which switcher action, whether it's swallowed,
/// and how it changes the active state.
@Suite("Key decision routing")
struct KeyDecisionTests {
    private typealias Decision = EventTapManager.KeyDecision

    private func decide(
        _ keyCode: Int,
        command: Bool = false,
        shift: Bool = false,
        active: Bool
    ) -> Decision {
        EventTapManager.decideKeyDown(
            keyCode: keyCode,
            command: command,
            shift: shift,
            isSwitcherActive: active
        )
    }

    private func decide(
        _ keyCode: Int,
        command: Bool = false,
        shift: Bool = false,
        active: Bool,
        filtering: Bool,
        latched: Bool = false,
        characters: String? = nil
    ) -> Decision {
        EventTapManager.decideKeyDown(
            keyCode: keyCode,
            command: command,
            shift: shift,
            isSwitcherActive: active,
            isFiltering: filtering,
            isLatched: latched,
            characters: characters
        )
    }

    // MARK: Cmd+Tab

    @Test func commandTabWhenIdleActivates() {
        let decision = decide(kVK_Tab, command: true, active: false)
        #expect(decision == Decision(action: .activate, swallow: true, isSwitcherActive: true))
    }

    @Test func commandTabWhenActiveAdvancesForward() {
        let decision = decide(kVK_Tab, command: true, active: true)
        #expect(decision == Decision(action: .advance(reverse: false), swallow: true, isSwitcherActive: true))
    }

    @Test func commandShiftTabReverses() {
        let decision = decide(kVK_Tab, command: true, shift: true, active: true)
        #expect(decision == Decision(action: .advance(reverse: true), swallow: true, isSwitcherActive: true))
    }

    @Test func tabWithoutCommandPassesThroughWhenIdle() {
        let decision = decide(kVK_Tab, command: false, active: false)
        #expect(decision == Decision(action: .none, swallow: false, isSwitcherActive: false))
    }

    // MARK: Idle pass-through

    @Test func nonTabKeyWhenIdlePassesThrough() {
        let decision = decide(kVK_ANSI_H, command: true, active: false)
        #expect(decision == Decision(action: .none, swallow: false, isSwitcherActive: false))
    }

    @Test func arrowKeyWhenIdlePassesThrough() {
        let decision = decide(kVK_DownArrow, active: false)
        #expect(decision == Decision(action: .none, swallow: false, isSwitcherActive: false))
    }

    // MARK: Commit / cancel

    @Test func escapeCancelsAndDeactivates() {
        let decision = decide(kVK_Escape, active: true)
        #expect(decision == Decision(action: .escape, swallow: true, isSwitcherActive: false))
    }

    @Test func returnCommitsAndDeactivates() {
        let decision = decide(kVK_Return, active: true)
        #expect(decision == Decision(action: .select, swallow: true, isSwitcherActive: false))
    }

    @Test func keypadEnterCommits() {
        let decision = decide(kVK_ANSI_KeypadEnter, active: true)
        #expect(decision == Decision(action: .select, swallow: true, isSwitcherActive: false))
    }

    // MARK: Arrow navigation

    @Test func downAndRightAdvanceForward() {
        #expect(decide(kVK_DownArrow, active: true).action == .advance(reverse: false))
        #expect(decide(kVK_RightArrow, active: true).action == .advance(reverse: false))
    }

    @Test func upAndLeftAdvanceReverse() {
        #expect(decide(kVK_UpArrow, active: true).action == .advance(reverse: true))
        #expect(decide(kVK_LeftArrow, active: true).action == .advance(reverse: true))
    }

    @Test func arrowKeysStaySwitcherActive() {
        let decision = decide(kVK_DownArrow, active: true)
        #expect(decision.swallow)
        #expect(decision.isSwitcherActive)
    }

    // MARK: Preview toggle

    @Test func pTogglesPreviewWithoutCommand() {
        let decision = decide(kVK_ANSI_P, active: true)
        #expect(decision == Decision(action: .togglePreview, swallow: true, isSwitcherActive: true))
    }

    // MARK: Cmd+H / Cmd+Q / Cmd+M on the selection

    @Test func commandHHidesSelected() {
        let decision = decide(kVK_ANSI_H, command: true, active: true)
        #expect(decision == Decision(action: .hideSelected, swallow: true, isSwitcherActive: true))
    }

    @Test func commandQQuitsSelected() {
        let decision = decide(kVK_ANSI_Q, command: true, active: true)
        #expect(decision == Decision(action: .quitSelected, swallow: true, isSwitcherActive: true))
    }

    @Test func commandMMinimizesSelected() {
        let decision = decide(kVK_ANSI_M, command: true, active: true)
        #expect(decision == Decision(action: .minimizeSelected, swallow: true, isSwitcherActive: true))
    }

    @Test func hWithoutCommandPassesThroughWhileActive() {
        // Plain "H" (no Cmd) while switching isn't a shortcut — let it through.
        let decision = decide(kVK_ANSI_H, command: false, active: true)
        #expect(decision == Decision(action: .none, swallow: false, isSwitcherActive: true))
    }

    @Test func unhandledKeyWhileActivePassesThrough() {
        let decision = decide(kVK_ANSI_A, command: true, active: true)
        #expect(decision == Decision(action: .none, swallow: false, isSwitcherActive: true))
    }

    // MARK: Cmd+F filter

    @Test func commandFWhileSwitchingActivatesFilter() {
        let decision = decide(kVK_ANSI_F, command: true, active: true)
        #expect(decision == Decision(action: .filterActivate, swallow: true, isSwitcherActive: true, isFiltering: true))
    }

    @Test func commandFWhenIdlePassesThroughToApp() {
        // Not switching: Cmd+F belongs to the frontmost app's own Find, untouched.
        let decision = decide(kVK_ANSI_F, command: true, active: false)
        #expect(decision == Decision(action: .none, swallow: false, isSwitcherActive: false))
    }

    @Test func commandFWhileAlreadyFilteringIsSwallowedNoOp() {
        // A repeat Cmd+F must not type an "f" into the query.
        let decision = decide(kVK_ANSI_F, command: true, active: true, filtering: true)
        #expect(decision == Decision(action: .none, swallow: true, isSwitcherActive: true, isFiltering: true))
    }

    // MARK: Cmd+, open settings

    @Test func commandCommaWhileSwitchingOpensSettings() {
        // The switcher is Tabby's main surface, so ⌘, opens Settings and
        // dismisses the HUD (deactivates) rather than leaking to the app behind.
        let decision = decide(kVK_ANSI_Comma, command: true, active: true)
        #expect(decision == Decision(action: .openSettings, swallow: true, isSwitcherActive: false))
    }

    @Test func commandCommaWhenIdlePassesThroughToApp() {
        // Not switching: ⌘, belongs to the frontmost app's own settings, untouched.
        let decision = decide(kVK_ANSI_Comma, command: true, active: false)
        #expect(decision == Decision(action: .none, swallow: false, isSwitcherActive: false))
    }

    @Test func commandCommaWhileFilteringStillOpensSettings() {
        // Even mid-filter, ⌘, opens Settings — Cmd is held, so it's never query text.
        let decision = decide(kVK_ANSI_Comma, command: true, active: true, filtering: true)
        #expect(decision == Decision(action: .openSettings, swallow: true, isSwitcherActive: false))
    }

    @Test func commaWithoutCommandPassesThroughWhileActive() {
        // Plain "," (no Cmd) isn't the settings shortcut — don't swallow it.
        let decision = decide(kVK_ANSI_Comma, command: false, active: true)
        #expect(decision == Decision(action: .none, swallow: false, isSwitcherActive: true))
    }

    // MARK: Filter text entry

    @Test func printableKeyBuildsQueryWhileFiltering() {
        let decision = decide(kVK_ANSI_A, active: true, filtering: true, characters: "a")
        #expect(decision == Decision(action: .filterInput("a"), swallow: true, isSwitcherActive: true, isFiltering: true))
    }

    @Test func deleteBackspacesWhileFiltering() {
        let decision = decide(kVK_Delete, active: true, filtering: true)
        #expect(decision == Decision(action: .filterBackspace, swallow: true, isSwitcherActive: true, isFiltering: true))
    }

    @Test func pTypesLetterInsteadOfTogglingPreviewWhileFiltering() {
        let decision = decide(kVK_ANSI_P, active: true, filtering: true, characters: "p")
        #expect(decision == Decision(action: .filterInput("p"), swallow: true, isSwitcherActive: true, isFiltering: true))
    }

    @Test func arrowsStillNavigateAndKeepFiltering() {
        let down = decide(kVK_DownArrow, active: true, filtering: true)
        #expect(down == Decision(action: .advance(reverse: false), swallow: true, isSwitcherActive: true, isFiltering: true, isLatched: true))
        let up = decide(kVK_UpArrow, active: true, filtering: true)
        #expect(up == Decision(action: .advance(reverse: true), swallow: true, isSwitcherActive: true, isFiltering: true, isLatched: true))
    }

    @Test func returnSelectsWhileFiltering() {
        let decision = decide(kVK_Return, active: true, filtering: true)
        #expect(decision == Decision(action: .select, swallow: true, isSwitcherActive: false))
    }

    @Test func escapeCancelsWhileFiltering() {
        let decision = decide(kVK_Escape, active: true, filtering: true)
        #expect(decision == Decision(action: .escape, swallow: true, isSwitcherActive: false))
    }

    @Test func nonPrintableKeyWhileFilteringIsSwallowedWithoutInput() {
        // Function keys and the like must not leak to the app, but add no text.
        let decision = decide(kVK_F1, active: true, filtering: true, characters: nil)
        #expect(decision == Decision(action: .none, swallow: true, isSwitcherActive: true, isFiltering: true))
    }

    // MARK: Arrow-key latching (Cmd release no longer commits)

    @Test func arrowKeysLatchTheHUDOpen() {
        #expect(decide(kVK_DownArrow, active: true).isLatched)
        #expect(decide(kVK_UpArrow, active: true).isLatched)
        #expect(decide(kVK_LeftArrow, active: true).isLatched)
        #expect(decide(kVK_RightArrow, active: true).isLatched)
    }

    @Test func commandTabDoesNotLatch() {
        // The classic quick switch must still commit on Cmd release.
        #expect(decide(kVK_Tab, command: true, active: false).isLatched == false)
        #expect(decide(kVK_Tab, command: true, active: true).isLatched == false)
    }

    @Test func freshCommandTabClearsStaleFilterAndLatch() {
        // Starting a new switch must not inherit filter/latch state stranded by a
        // prior session — otherwise releasing Cmd is swallowed and the selection
        // never commits.
        let decision = decide(kVK_Tab, command: true, active: false, filtering: true, latched: true)
        #expect(decision == Decision(action: .activate, swallow: true, isSwitcherActive: true))
        #expect(decision.isFiltering == false)
        #expect(decision.isLatched == false)
    }

    @Test func advancingWithinSessionKeepsFilterAndLatch() {
        // A second Tab while already switching stays in the same session, so the
        // active filter/latch state carries forward.
        let decision = decide(kVK_Tab, command: true, active: true, filtering: true, latched: true)
        #expect(decision == Decision(action: .advance(reverse: false), swallow: true, isSwitcherActive: true, isFiltering: true, isLatched: true))
    }

    @Test func latchIsCarriedForwardByLaterKeys() {
        // Cmd+H without an existing latch leaves it clear...
        #expect(decide(kVK_ANSI_H, command: true, active: true, filtering: false).isLatched == false)
        // ...but once latched, a later action (e.g. Cmd+H) preserves it.
        let latched = decide(kVK_ANSI_H, command: true, active: true, filtering: false, latched: true)
        #expect(latched.isLatched)
    }
}
