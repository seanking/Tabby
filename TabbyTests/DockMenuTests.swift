import CoreGraphics
import Testing
@testable import Tabby

/// Covers `dockMenuGroups`, which groups the switcher's window list by app for
/// the Dock icon's right-click menu, with apps and windows alphabetized.
@Suite("Dock menu grouping")
struct DockMenuTests {
    private func window(_ id: CGWindowID, pid: pid_t, owner: String, title: String? = nil) -> WindowInfo {
        WindowInfo(id: id, pid: pid, ownerName: owner, title: title ?? "Window \(id)", bounds: .zero)
    }

    @Test func groupsWindowsByApp() {
        // Given
        let windows = [
            window(1, pid: 10, owner: "Safari"),
            window(2, pid: 20, owner: "Mail"),
            window(3, pid: 10, owner: "Safari"),
        ]

        // When
        let groups = dockMenuGroups(for: windows)

        // Then
        #expect(groups.map(\.appName) == ["Mail", "Safari"])
        #expect(groups[0].windows.map(\.id) == [2])
        #expect(groups[1].windows.map(\.id) == [1, 3])
    }

    @Test func ordersAppsAlphabeticallyIgnoringCase() {
        // Given
        let windows = [
            window(1, pid: 10, owner: "Safari"),
            window(2, pid: 20, owner: "iTerm"),
            window(3, pid: 30, owner: "Mail"),
        ]

        // When
        let groups = dockMenuGroups(for: windows)

        // Then
        #expect(groups.map(\.appName) == ["iTerm", "Mail", "Safari"])
    }

    @Test func ordersWindowsAlphabeticallyByShownTitle() {
        // Given: most-recent-first input, with a number that must sort
        // numerically ("2" before "10") rather than character by character.
        let windows = [
            window(1, pid: 10, owner: "Safari", title: "Window 10"),
            window(2, pid: 10, owner: "Safari", title: "apple.com"),
            window(3, pid: 10, owner: "Safari", title: "Window 2"),
        ]

        // When
        let groups = dockMenuGroups(for: windows)

        // Then
        #expect(groups[0].windows.map(\.id) == [2, 3, 1])
    }

    @Test func separatesProcessesWithTheSameNameInStableOrder() {
        // Given
        let windows = [
            window(1, pid: 11, owner: "Terminal"),
            window(2, pid: 10, owner: "Terminal"),
        ]

        // When
        let groups = dockMenuGroups(for: windows)

        // Then
        #expect(groups.map(\.pid) == [10, 11])
    }

    @Test func emptyListProducesNoGroups() {
        #expect(dockMenuGroups(for: []).isEmpty)
    }
}
