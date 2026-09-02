import Testing
@testable import Tabby

/// Covers the wrap-around selection logic shared by Tab/Shift+Tab and the arrow
/// keys (`SwitcherController.nextIndex`).
@Suite("Selection navigation")
struct NavigationTests {
    @Test func forwardAdvances() {
        // Given
        let index = 0

        // When
        let next = SwitcherController.nextIndex(from: index, reverse: false, count: 3)

        // Then
        #expect(next == 1)
    }

    @Test func forwardWrapsPastEnd() {
        // Given
        let index = 2

        // When
        let next = SwitcherController.nextIndex(from: index, reverse: false, count: 3)

        // Then
        #expect(next == 0)
    }

    @Test func reverseDecrements() {
        // Given
        let index = 2

        // When
        let next = SwitcherController.nextIndex(from: index, reverse: true, count: 3)

        // Then
        #expect(next == 1)
    }

    @Test func reverseWrapsBeforeStart() {
        // Given
        let index = 0

        // When
        let next = SwitcherController.nextIndex(from: index, reverse: true, count: 3)

        // Then
        #expect(next == 2)
    }

    @Test func emptyListReturnsZero() {
        // Given
        let count = 0

        // When
        let next = SwitcherController.nextIndex(from: 0, reverse: false, count: count)

        // Then
        #expect(next == 0)
    }

    @Test func singleItemStaysPut() {
        // Given
        let count = 1

        // When
        let forward = SwitcherController.nextIndex(from: 0, reverse: false, count: count)
        let reverse = SwitcherController.nextIndex(from: 0, reverse: true, count: count)

        // Then
        #expect(forward == 0)
        #expect(reverse == 0)
    }
}
