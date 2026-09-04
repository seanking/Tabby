import Testing
@testable import Tabby

/// Covers `WindowManager.isBadgeCount`, which decides whether a Dock tile's
/// `AXStatusLabel` is a real notification count (rendered as a badge) versus
/// other transient text a tile can expose.
@Suite("Badge count detection")
struct BadgeCountTests {
    @Test func plainNumberIsABadge() {
        #expect(WindowManager.isBadgeCount("3"))
    }

    @Test func multiDigitNumberIsABadge() {
        #expect(WindowManager.isBadgeCount("128"))
    }

    @Test func trailingPlusIsABadge() {
        #expect(WindowManager.isBadgeCount("99+"))
    }

    @Test func emptyStringIsNotABadge() {
        #expect(WindowManager.isBadgeCount("") == false)
    }

    @Test func barePlusIsNotABadge() {
        // A "+" with no leading digits isn't a count.
        #expect(WindowManager.isBadgeCount("+") == false)
    }

    @Test func lettersAreNotABadge() {
        #expect(WindowManager.isBadgeCount("Mon") == false)
    }

    @Test func decimalIsNotABadge() {
        // A '.' isn't a digit, so version/decimal-like labels are rejected.
        #expect(WindowManager.isBadgeCount("3.5") == false)
    }

    @Test func timeLikeLabelIsNotABadge() {
        #expect(WindowManager.isBadgeCount("12:30") == false)
    }

    @Test func plusInMiddleIsNotABadge() {
        // The '+' is only allowed as a trailing suffix.
        #expect(WindowManager.isBadgeCount("1+2") == false)
    }
}
