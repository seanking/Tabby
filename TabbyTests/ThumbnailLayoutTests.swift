import CoreGraphics
import Testing
@testable import Tabby

/// Covers `switcherTileSize`, the box each snapshot is fitted into in the
/// thumbnails style: it follows the Appearance "Size" scale and stays a
/// reasonable share of the display.
@Suite("Thumbnail tile size")
struct ThumbnailTileSizeTests {
    private let screen = CGSize(width: 1440, height: 900)

    @Test func oneHundredPercentIsTheBaselineBox() {
        let size = switcherTileSize(scale: 1.0, screenSize: screen)

        #expect(Double(size.width) == SettingsKey.baseTileWidth)
        #expect(Double(size.height) == SettingsKey.baseTileHeight)
    }

    @Test func scalingGrowsBothDimensionsTogether() {
        let size = switcherTileSize(scale: 1.5, screenSize: screen)

        #expect(Double(size.width) == SettingsKey.baseTileWidth * 1.5)
        #expect(Double(size.height) == SettingsKey.baseTileHeight * 1.5)
    }

    @Test func aSmallScreenCapsTheBox() {
        let small = CGSize(width: 1000, height: 600)
        let size = switcherTileSize(scale: 2.0, screenSize: small)

        #expect(size.width == small.width * 0.3)
        #expect(size.height == small.height * 0.3)
    }

    @Test(arguments: [-1.0, 0.0, 5.0])
    func outOfRangeScalesAreClamped(scale: Double) {
        let size = switcherTileSize(scale: scale, screenSize: CGSize(width: 5000, height: 3000))
        let smallest = switcherTileSize(scale: SettingsKey.scaleRange.lowerBound, screenSize: CGSize(width: 5000, height: 3000))
        let largest = switcherTileSize(scale: SettingsKey.scaleRange.upperBound, screenSize: CGSize(width: 5000, height: 3000))

        #expect(size.width >= smallest.width)
        #expect(size.width <= largest.width)
    }
}

/// Covers `thumbnailGridLayout`: tiles wrap onto rows at the available width,
/// and shrink when there are too many rows to fit, so the grid never scrolls.
@Suite("Thumbnail grid layout")
struct ThumbnailGridLayoutTests {
    private let m = ThumbnailTileMetrics.self
    private let box = CGSize(width: 200, height: 125)
    private let titleHeight: CGFloat = 18
    private let roomy = CGSize(width: 1300, height: 760)

    private func layout(_ count: Int, available: CGSize? = nil) -> ThumbnailGridLayout {
        thumbnailGridLayout(
            tileCount: count,
            boxSize: box,
            titleHeight: titleHeight,
            availableSize: available ?? roomy
        )
    }

    @Test func aFewTilesSitOnOneRowAtFullSize() {
        let grid = layout(3)

        #expect(grid.columns == 3)
        #expect(grid.rows(for: 3) == 1)
        #expect(grid.boxSize == box)
    }

    @Test func tilesWrapOntoRowsAtTheAvailableWidth() {
        // 216pt tiles + 8pt gaps in 1276pt of inner width: 5 across.
        let grid = layout(12)

        #expect(grid.columns == 5)
        #expect(grid.rows(for: 12) == 3)
        #expect(grid.gridSize(rows: 3).width <= roomy.width)
    }

    @Test func theGridIsNeverWiderOrTallerThanTheRoomWhenItCanFit() {
        let grid = layout(40)
        let size = grid.gridSize(rows: grid.rows(for: 40))

        #expect(size.width <= roomy.width)
        #expect(size.height <= roomy.height)
    }

    @Test func tooManyRowsShrinkTheTilesAndFitMoreAcross() {
        let grid = layout(40)

        #expect(grid.boxSize.width < box.width)
        #expect(grid.columns > 5)
    }

    @Test func shrinkingStopsAtTheMinimum() {
        let grid = layout(500)

        #expect(grid.boxSize.width >= (box.width * m.minShrink).rounded(.down) - 1)
    }

    @Test func anEmptyListKeepsOneRow() {
        let grid = layout(0)

        #expect(grid.columns == 1)
        #expect(grid.rows(for: 0) == 1)
    }

    @Test func aNarrowRoomStillFitsOneTilePerRow() {
        let grid = layout(3, available: CGSize(width: 100, height: 2000))

        #expect(grid.columns == 1)
        #expect(grid.rows(for: 3) == 3)
    }
}
