import CoreGraphics
import Testing
@testable import Tabby

/// `WindowInfo` identifies windows by their CoreGraphics id; equality must be
/// id-based so the switcher can de-duplicate windows across enumeration passes.
@Suite("WindowInfo")
struct WindowInfoTests {
    @Test func equalityIsByIDOnly() {
        // Given
        let a = WindowInfo(id: 42, pid: 1, ownerName: "A", title: "x", bounds: .zero)
        let b = WindowInfo(
            id: 42,
            pid: 2,
            ownerName: "B",
            title: "y",
            bounds: CGRect(x: 1, y: 2, width: 3, height: 4),
            isHidden: true,
            isMinimized: true
        )

        // When
        let isEqual = a == b

        // Then
        #expect(isEqual)
    }

    @Test func differentIDsAreNotEqual() {
        // Given
        let a = WindowInfo(id: 1, pid: 1, ownerName: "A", title: "x", bounds: .zero)
        let b = WindowInfo(id: 2, pid: 1, ownerName: "A", title: "x", bounds: .zero)

        // When
        let isEqual = a == b

        // Then
        #expect(isEqual == false)
    }

    @Test func defaultsAreVisibleAndRestored() {
        // Given
        let window = WindowInfo(id: 1, pid: 1, ownerName: "A", title: "x", bounds: .zero)

        // When
        let (hidden, minimized) = (window.isHidden, window.isMinimized)

        // Then
        #expect(hidden == false)
        #expect(minimized == false)
    }
}
