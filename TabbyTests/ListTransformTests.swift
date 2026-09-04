import CoreGraphics
import Testing
@testable import Tabby

/// Covers the pure list transformations behind ⌘H (hide → gray), ⌘Q (quit →
/// remove), and ⌘M (minimize → gray), plus the selection clamping on removal.
@Suite("Window list transformations")
struct ListTransformTests {
    private func window(_ id: CGWindowID, pid: pid_t) -> WindowInfo {
        WindowInfo(id: id, pid: pid, ownerName: "App\(pid)", title: "t", bounds: .zero)
    }

    private func window(_ id: CGWindowID, owner: String, title: String) -> WindowInfo {
        WindowInfo(id: id, pid: pid_t(id), ownerName: owner, title: title, bounds: .zero)
    }

    // MARK: filter

    @Test func emptyQueryReturnsEverything() {
        let windows = [window(1, owner: "Safari", title: "Home"), window(2, owner: "Xcode", title: "main")]
        #expect(SwitcherController.filter(windows, query: "   ").map(\.id) == [1, 2])
    }

    @Test func filterMatchesAppName() {
        let windows = [window(1, owner: "Safari", title: "Home"), window(2, owner: "Xcode", title: "main")]
        #expect(SwitcherController.filter(windows, query: "xco").map(\.id) == [2])
    }

    @Test func filterMatchesWindowTitle() {
        let windows = [window(1, owner: "Safari", title: "Inbox"), window(2, owner: "Xcode", title: "main")]
        #expect(SwitcherController.filter(windows, query: "inbox").map(\.id) == [1])
    }

    @Test func filterIsCaseInsensitive() {
        let windows = [window(1, owner: "Safari", title: "Home")]
        #expect(SwitcherController.filter(windows, query: "SAFARI").map(\.id) == [1])
    }

    @Test func filterWithNoMatchesIsEmpty() {
        let windows = [window(1, owner: "Safari", title: "Home")]
        #expect(SwitcherController.filter(windows, query: "zzz").isEmpty)
    }

    // MARK: markingHidden

    @Test func markingHiddenGraysEveryWindowOfApp() {
        // Given
        let windows = [window(1, pid: 10), window(2, pid: 10), window(3, pid: 20)]

        // When
        let result = SwitcherController.markingHidden(pid: 10, in: windows)

        // Then
        #expect(result[0].isHidden)
        #expect(result[1].isHidden)
        #expect(result[2].isHidden == false)
    }

    @Test func markingHiddenPreservesOrderAndCount() {
        // Given
        let windows = [window(1, pid: 10), window(2, pid: 20)]

        // When
        let result = SwitcherController.markingHidden(pid: 10, in: windows)

        // Then
        #expect(result.map(\.id) == [1, 2])
    }

    // MARK: markingMinimized

    @Test func markingMinimizedAffectsOnlyThatWindow() {
        // Given
        let windows = [window(1, pid: 10), window(2, pid: 10)]

        // When
        let result = SwitcherController.markingMinimized(id: 1, in: windows)

        // Then
        #expect(result[0].isMinimized)
        #expect(result[1].isMinimized == false)
    }

    // MARK: removingApp

    @Test func removingAppDropsAllItsWindows() {
        // Given
        let windows = [window(1, pid: 10), window(2, pid: 20), window(3, pid: 10)]

        // When
        let result = SwitcherController.removingApp(pid: 10, from: windows, selectedIndex: 0)

        // Then
        #expect(result.windows.map(\.id) == [2])
    }

    @Test func removingAppClampsSelectionIntoRange() {
        // Given
        let windows = [window(1, pid: 10), window(2, pid: 20), window(3, pid: 30)]

        // When
        let result = SwitcherController.removingApp(pid: 30, from: windows, selectedIndex: 2)

        // Then
        #expect(result.windows.count == 2)
        #expect(result.selectedIndex == 1)
    }

    @Test func removingAppKeepsInRangeSelectionUnchanged() {
        // Given
        let windows = [window(1, pid: 10), window(2, pid: 20), window(3, pid: 30)]

        // When
        let result = SwitcherController.removingApp(pid: 30, from: windows, selectedIndex: 0)

        // Then
        #expect(result.selectedIndex == 0)
    }

    @Test func removingAllWindowsResetsSelectionToZero() {
        // Given
        let windows = [window(1, pid: 10), window(2, pid: 10)]

        // When
        let result = SwitcherController.removingApp(pid: 10, from: windows, selectedIndex: 1)

        // Then
        #expect(result.windows.isEmpty)
        #expect(result.selectedIndex == 0)
    }
}
