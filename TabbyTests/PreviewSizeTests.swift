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

/// Covers `previewCardLayout`, which places the floating preview card beside
/// the HUD: which side it takes, how the snapshot is fitted, and keeping both
/// the card and its notch where they belong.
@Suite("Preview card layout")
struct PreviewCardLayoutTests {
    private let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let maxImage = CGSize(width: 320, height: 200)
    /// A HUD centered on the screen.
    private let centeredHUD = CGRect(x: 520, y: 250, width: 400, height: 400)

    private func layout(
        image: CGSize = CGSize(width: 1600, height: 1000),
        hud: CGRect? = nil,
        anchorY: CGFloat = 450,
        maxImage: CGSize? = nil
    ) -> PreviewCardLayout {
        previewCardLayout(
            imageSize: image,
            maxImageSize: maxImage ?? self.maxImage,
            hudFrame: hud ?? centeredHUD,
            anchorY: anchorY,
            visibleFrame: visible
        )
    }

    @Test func aCenteredHUDGetsTheCardOnTheRightWithTheNotchFacingIt() {
        let card = layout()

        #expect(card.notchEdge == .leading)
        #expect(card.frame.minX == centeredHUD.maxX + PreviewCardMetrics.gap)
    }

    @Test func aHUDNearTheRightEdgeGetsTheCardOnTheLeft() {
        let hud = CGRect(x: 1000, y: 250, width: 400, height: 400)
        let card = layout(hud: hud)

        #expect(card.notchEdge == .trailing)
        #expect(card.frame.maxX == hud.minX - PreviewCardMetrics.gap)
    }

    @Test func theCardNeverOverlapsTheHUDWhenThereIsRoom() {
        let card = layout()

        #expect(!card.frame.intersects(centeredHUD))
    }

    /// The snapshot keeps the window's shape instead of being letterboxed into
    /// the fixed Size box.
    @Test func theSnapshotKeepsTheWindowsAspectRatio() {
        let tall = layout(image: CGSize(width: 800, height: 1200))

        #expect(tall.imageSize.height == maxImage.height)
        #expect(abs(tall.imageSize.width / tall.imageSize.height - 800.0 / 1200.0) < 0.01)
    }

    @Test func theSnapshotShrinksToFitTheRoomBesideTheHUD() {
        // A wide HUD leaves only ~200pt on either side, less than the 640pt box
        let hud = CGRect(x: 200, y: 250, width: 1040, height: 400)
        let card = layout(hud: hud, maxImage: CGSize(width: 640, height: 400))

        #expect(card.frame.minX >= hud.maxX)
        #expect(card.frame.maxX <= visible.maxX)
    }

    @Test func theCardIsCenteredOnTheSelectedRow() {
        let card = layout(anchorY: 500)

        #expect(abs(card.frame.midY - 500) <= 1)
        #expect(abs(card.notchY - card.frame.height / 2) <= 1)
    }

    /// A row near the bottom of a tall HUD would push the card off screen;
    /// the card is clamped, but the notch still points at the row.
    @Test func theCardStaysOnScreenButTheNotchFollowsTheRow() {
        let hud = CGRect(x: 520, y: 20, width: 400, height: 860)
        let card = layout(hud: hud, anchorY: 60)

        #expect(card.frame.minY >= visible.minY)
        #expect(abs((card.frame.maxY - card.notchY) - 60) <= 1)
    }

    @Test func theNotchStaysClearOfTheCardsCorners() {
        let hud = CGRect(x: 520, y: 20, width: 400, height: 860)
        let card = layout(hud: hud, anchorY: 21)
        let inset = PreviewCardMetrics.cornerRadius + PreviewCardMetrics.notchWidth / 2

        #expect(card.notchY >= inset)
        #expect(card.notchY <= card.frame.height - inset)
    }
}
