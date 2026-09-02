import Testing
@testable import Tabby

/// Covers `switcherDisplayName`, which formats each row's label
/// ("AppName — Window Title"), reduces multi-segment titles to their last
/// em-dash segment, and honors the "Show app name" setting.
@Suite("Switcher display name")
struct DisplayNameTests {
    private func window(owner: String, title: String) -> WindowInfo {
        WindowInfo(id: 1, pid: 1, ownerName: owner, title: title, bounds: .zero)
    }

    @Test func combinesAppAndTitle() {
        // Given
        let window = window(owner: "Safari", title: "Google")

        // When
        let name = switcherDisplayName(for: window, showAppName: true)

        // Then
        #expect(name == "Safari — Google")
    }

    @Test func reducesMultiSegmentTitleToLastSegment() {
        // Given
        let window = window(owner: "Safari", title: "Personal — Google")

        // When
        let name = switcherDisplayName(for: window, showAppName: true)

        // Then
        #expect(name == "Safari — Google")
    }

    @Test func emptyTitleShowsAppOnly() {
        // Given
        let window = window(owner: "Finder", title: "")

        // When
        let name = switcherDisplayName(for: window, showAppName: true)

        // Then
        #expect(name == "Finder")
    }

    @Test func emptyAppShowsTitleOnly() {
        // Given
        let window = window(owner: "", title: "Some Window")

        // When
        let name = switcherDisplayName(for: window, showAppName: true)

        // Then
        #expect(name == "Some Window")
    }

    @Test func bothEmptyProducesEmptyString() {
        // Given
        let window = window(owner: "", title: "")

        // When
        let name = switcherDisplayName(for: window, showAppName: true)

        // Then
        #expect(name == "")
    }

    @Test func hidingAppNameShowsTitleOnly() {
        // Given
        let window = window(owner: "Safari", title: "Personal — Google")

        // When
        let name = switcherDisplayName(for: window, showAppName: false)

        // Then
        #expect(name == "Google")
    }

    @Test func hidingAppNameFallsBackToAppWhenNoTitle() {
        // Given
        let window = window(owner: "Safari", title: "")

        // When
        let name = switcherDisplayName(for: window, showAppName: false)

        // Then
        #expect(name == "Safari")
    }

    @Test func trimsSurroundingWhitespace() {
        // Given
        let window = window(owner: "  Safari  ", title: "  Google  ")

        // When
        let name = switcherDisplayName(for: window, showAppName: true)

        // Then
        #expect(name == "Safari — Google")
    }

    @Test func singleSegmentTitleIsUnchanged() {
        // Given
        let window = window(owner: "Reminders", title: "Reminders")

        // When
        let name = switcherDisplayName(for: window, showAppName: true)

        // Then
        #expect(name == "Reminders — Reminders")
    }
}
