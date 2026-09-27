import CoreGraphics
import Testing
@testable import Tabby

/// Covers `switcherPreviewSize`, the Preview "Size" setting's layout math: 100%
/// is the baseline pane, larger scales grow it proportionally, and nothing may
/// push the pane past the display.
@Suite("Preview size")
struct PreviewSizeTests {
    private let screen = CGSize(width: 1440, height: 900)

    @Test func oneHundredPercentIsTheBaselinePane() {
        let size = switcherPreviewSize(scale: 1.0, screenSize: screen)

        #expect(Double(size.width) == SettingsKey.basePreviewWidth)
        #expect(Double(size.height) == SettingsKey.basePreviewHeight)
    }

    @Test func largerScalesGrowBothDimensionsTogether() {
        let size = switcherPreviewSize(scale: 2.0, screenSize: screen)

        #expect(Double(size.width) == SettingsKey.basePreviewWidth * 2)
        #expect(Double(size.height) == SettingsKey.basePreviewHeight * 2)
    }

    /// Growing both dimensions by the same factor keeps the pane's aspect ratio,
    /// so a snapshot is letterboxed identically at every size.
    @Test func scalingPreservesThePaneAspectRatio() {
        let base = switcherPreviewSize(scale: 1.0, screenSize: screen)
        let grown = switcherPreviewSize(scale: 2.5, screenSize: screen)

        #expect(grown.width / grown.height == base.width / base.height)
    }

    // MARK: Limits

    @Test func widthIsCappedToTheScreen() {
        // Given a narrow display, where 3x the base width wouldn't fit
        let narrow = CGSize(width: 800, height: 1200)
        let size = switcherPreviewSize(scale: 3.0, screenSize: narrow)

        #expect(Double(size.width) == Double(narrow.width) * 0.6)
    }

    @Test func heightIsCappedToTheScreen() {
        // Given a short display, where 3x the base height wouldn't fit
        let short = CGSize(width: 2560, height: 700)
        let size = switcherPreviewSize(scale: 3.0, screenSize: short)

        #expect(Double(size.height) == Double(short.height) * 0.8)
    }

    @Test func aRoomyScreenIsNotCapped() {
        let size = switcherPreviewSize(scale: 3.0, screenSize: CGSize(width: 3840, height: 2160))

        #expect(Double(size.width) == SettingsKey.basePreviewWidth * 3)
        #expect(Double(size.height) == SettingsKey.basePreviewHeight * 3)
    }

    /// A value stored outside the slider's range — a hand-edited preference, or
    /// one written by a future build — must not make the preview vanish or take
    /// over the screen.
    @Test(arguments: [-1.0, 0.0, 0.5, 4.0, 100.0])
    func outOfRangeScalesAreClampedToTheAllowedRange(scale: Double) {
        let size = switcherPreviewSize(scale: scale, screenSize: screen)
        let smallest = switcherPreviewSize(scale: SettingsKey.previewScaleRange.lowerBound, screenSize: screen)
        let largest = switcherPreviewSize(scale: SettingsKey.previewScaleRange.upperBound, screenSize: screen)

        #expect(size.width >= smallest.width)
        #expect(size.width <= largest.width)
        #expect(size.height >= smallest.height)
        #expect(size.height <= largest.height)
    }

    @Test func theDefaultScaleIsTheBaselinePane() {
        let size = switcherPreviewSize(scale: SettingsKey.defaultPreviewScale, screenSize: screen)

        #expect(Double(size.width) == SettingsKey.basePreviewWidth)
        #expect(Double(size.height) == SettingsKey.basePreviewHeight)
    }
}
