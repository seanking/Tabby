import SwiftUI

/// Fixed measurements of a thumbnail tile, shared by the layout math (which
/// sizes the grid) and the tile view that draws it.
enum ThumbnailTileMetrics {
    /// Inset between the tile's selection highlight and its snapshot/title.
    static let padding: CGFloat = 8
    /// Gap between the snapshot and the title beneath it.
    static let titleSpacing: CGFloat = 6
    /// Gap between neighbouring tiles, both across and down.
    static let spacing: CGFloat = 8
    /// Inset between the HUD's edge and the grid of tiles.
    static let outerPadding: CGFloat = 12
    /// Largest share of the display's width the grid may span.
    static let maxWidthFraction: CGFloat = 0.9
    /// Largest share of the display's height the whole HUD may span.
    static let maxHeightFraction: CGFloat = 0.85
    /// Height set aside above the grid for the filter bar, so showing it can't
    /// push the HUD past `maxHeightFraction`.
    static let filterBarReserve: CGFloat = 48
    /// Smallest the snapshot box may shrink (as a fraction of its "Size")
    /// to fit every tile on screen. Below this, tiles stay legible and the
    /// grid is allowed to run long instead.
    static let minShrink: CGFloat = 0.3
}

/// The box each window's snapshot is fitted into at the Appearance "Size"
/// scale. 100% is the baseline box and other scales grow or shrink both
/// dimensions together. Capped to a fraction of the screen so an extreme
/// scale on a small display still leaves room for several tiles. A free
/// function so the layout math can be tested without building a view.
func switcherTileSize(scale: Double, screenSize: CGSize) -> CGSize {
    let range = SettingsKey.scaleRange
    let clamped = min(max(scale, range.lowerBound), range.upperBound)
    return CGSize(
        width: min(SettingsKey.baseTileWidth * clamped, screenSize.width * 0.3),
        height: min(SettingsKey.baseTileHeight * clamped, screenSize.height * 0.3)
    )
}

/// How the thumbnails grid is arranged: how many tiles go across each row and
/// how big each tile's snapshot box is.
struct ThumbnailGridLayout: Equatable {
    /// Tiles per row (at least 1).
    var columns: Int
    /// The box each snapshot is fitted into, possibly shrunk from the "Size"
    /// box so every tile fits on screen.
    var boxSize: CGSize
    /// One whole tile: snapshot box plus its selection padding and title.
    var tileSize: CGSize

    /// Rows needed to show `count` tiles (at least 1, so an empty filter
    /// result keeps a row's worth of height).
    func rows(for count: Int) -> Int {
        max(1, (count + columns - 1) / columns)
    }

    /// The grid's full size with `rows` rows, outer padding included.
    func gridSize(rows: Int) -> CGSize {
        let m = ThumbnailTileMetrics.self
        let columns = CGFloat(columns)
        let rows = CGFloat(max(rows, 1))
        return CGSize(
            width: columns * tileSize.width + (columns - 1) * m.spacing + m.outerPadding * 2,
            height: rows * tileSize.height + (rows - 1) * m.spacing + m.outerPadding * 2
        )
    }
}

/// Lays out `tileCount` tiles in rows that wrap at the available width, so
/// the switcher never scrolls. When that many rows would be taller than the
/// available height, the snapshot box shrinks (which also fits more tiles per
/// row) until the grid fits, down to `minShrink`. `availableSize` is the most
/// room the grid may take, outer padding included. A free function so the
/// layout can be tested without building a view.
func thumbnailGridLayout(
    tileCount: Int,
    boxSize: CGSize,
    titleHeight: CGFloat,
    availableSize: CGSize
) -> ThumbnailGridLayout {
    let m = ThumbnailTileMetrics.self
    let count = max(tileCount, 1)
    let innerWidth = availableSize.width - m.outerPadding * 2
    let innerHeight = availableSize.height - m.outerPadding * 2

    var shrink: CGFloat = 1
    while true {
        let box = CGSize(
            width: (boxSize.width * shrink).rounded(.down),
            height: (boxSize.height * shrink).rounded(.down)
        )
        let tile = CGSize(
            width: box.width + m.padding * 2,
            height: box.height + m.padding * 2 + m.titleSpacing + titleHeight
        )
        let fitting = Int((innerWidth + m.spacing) / (tile.width + m.spacing))
        let columns = max(1, min(count, fitting))
        let layout = ThumbnailGridLayout(columns: columns, boxSize: box, tileSize: tile)

        let rows = CGFloat(layout.rows(for: count))
        let height = rows * tile.height + (rows - 1) * m.spacing
        if height <= innerHeight || shrink * 0.95 < m.minShrink {
            return layout
        }
        shrink *= 0.95
    }
}

/// The "Thumbnails" switcher style: a grid of window snapshots that wraps
/// onto as many centered rows as it needs, each with its title underneath and the
/// app's icon (plus any notification badge) pinned to the snapshot's lower
/// corner. Shares the controller, the filter, and the mouse/keyboard behavior
/// with the list style.
struct ThumbnailSwitcherView: View {
    @ObservedObject var controller: SwitcherController
    @AppStorage(SettingsKey.uiScale) private var scale = SettingsKey.defaultScale
    @AppStorage(SettingsKey.alwaysShowFilter) private var alwaysShowFilter = SettingsKey.defaultAlwaysShowFilter

    private var fontSize: CGFloat { SettingsKey.baseFontSize * scale }

    var body: some View {
        let layout = gridLayout
        let gridSize = layout.gridSize(rows: layout.rows(for: controller.windows.count))
        VStack(spacing: 0) {
            if alwaysShowFilter || controller.filterActive {
                SwitcherFilterBar(
                    controller: controller,
                    width: gridSize.width - ThumbnailTileMetrics.outerPadding * 2
                )
            }
            VStack(alignment: .center, spacing: ThumbnailTileMetrics.spacing) {
                ForEach(rowRanges(columns: layout.columns), id: \.lowerBound) { range in
                    HStack(spacing: ThumbnailTileMetrics.spacing) {
                        ForEach(range, id: \.self) { index in
                            tile(at: index, layout: layout)
                        }
                    }
                }
            }
            .padding(ThumbnailTileMetrics.outerPadding)
            // Fixed to the grid's size so a short last row (or a filtered
            // list) is centered instead of narrowing the HUD.
            .frame(width: gridSize.width, height: gridSize.height, alignment: .top)
        }
        .switcherHUDChrome()
    }

    private func tile(at index: Int, layout: ThumbnailGridLayout) -> some View {
        let window = controller.windows[index]
        return WindowTile(
            window: window,
            thumbnail: controller.thumbnails[window.id],
            icon: controller.icons[window.pid],
            badge: controller.badges[window.pid],
            isSelected: index == controller.selectedIndex,
            boxSize: layout.boxSize,
            titleHeight: titleHeight
        )
        // Same pointer behavior as the list's rows: hover selects (once the
        // pointer really moves), click commits.
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            if case .active = phase { controller.hover(index: index) }
        }
        .onTapGesture {
            controller.choose(index: index)
        }
        .id(window.id)
    }

    /// The window indices on each row of the grid.
    private func rowRanges(columns: Int) -> [Range<Int>] {
        stride(from: 0, to: controller.windows.count, by: columns).map { start in
            start..<min(start + columns, controller.windows.count)
        }
    }

    /// Visible frame of the display the HUD is shown on, which the size caps
    /// are measured against. Falls back to `NSScreen.main` before the
    /// controller has placed the HUD on a display.
    private var displayFrame: CGRect? {
        controller.screenFrame ?? NSScreen.main?.visibleFrame
    }

    /// Height reserved for a tile's one-line title at the current font size.
    private var titleHeight: CGFloat {
        (fontSize * 1.35).rounded(.up)
    }

    /// Laid out for the full, unfiltered list so filtering can't change the
    /// columns, the tile size, or the HUD's width — it only drops rows.
    private var gridLayout: ThumbnailGridLayout {
        let m = ThumbnailTileMetrics.self
        let screen = displayFrame?.size ?? CGSize(width: 1200, height: 900)
        return thumbnailGridLayout(
            tileCount: controller.allWindows.count,
            boxSize: switcherTileSize(scale: scale, screenSize: screen),
            titleHeight: titleHeight,
            availableSize: CGSize(
                width: screen.width * m.maxWidthFraction,
                height: screen.height * m.maxHeightFraction - m.filterBarReserve
            )
        )
    }
}

/// One window in the grid: its snapshot fitted into the tile's box, the app
/// icon (with any notification badge) on the snapshot's lower-trailing corner,
/// and the window's title underneath.
private struct WindowTile: View {
    let window: WindowInfo
    let thumbnail: NSImage?
    let icon: NSImage?
    let badge: String?
    let isSelected: Bool
    let boxSize: CGSize
    let titleHeight: CGFloat

    @AppStorage(SettingsKey.showAppName) private var showAppName = true
    @AppStorage(SettingsKey.showBadges) private var showBadges = true
    @AppStorage(SettingsKey.uiScale) private var scale = SettingsKey.defaultScale

    private var fontSize: CGFloat { SettingsKey.baseFontSize * scale }
    private var badgeSize: CGFloat { SettingsKey.baseBadgeSize * scale }
    /// The corner icon tracks the snapshot box, so tiles shrunk to fit the
    /// screen don't end up with an icon covering most of the snapshot.
    private var iconSize: CGFloat {
        min(SettingsKey.baseTileIconSize * scale, boxSize.height * 0.4)
    }

    /// Hidden apps are shown grayed out, as in the list.
    private var isDimmed: Bool {
        window.isHidden
    }

    var body: some View {
        VStack(spacing: ThumbnailTileMetrics.titleSpacing) {
            snapshot
                .frame(width: boxSize.width, height: boxSize.height)
                .saturation(isDimmed ? 0 : 1)
                .opacity(isDimmed ? 0.5 : 1)

            Text(switcherDisplayName(for: window, showAppName: showAppName))
                .font(.system(size: fontSize))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(Color.primary)
                .frame(width: boxSize.width, height: titleHeight)
        }
        .padding(ThumbnailTileMetrics.padding)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.35) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
        )
    }

    /// The window's snapshot at its own aspect ratio, with the app icon pinned
    /// to the image's corner (not the box's, which may be wider or taller).
    /// Until a snapshot arrives — or without Screen Recording access — a large
    /// app icon on a faint card stands in for it. The icon is one view in both
    /// cases (only its size and alignment change), so a snapshot arriving
    /// doesn't recreate it and replay its selection reaction.
    private var snapshot: some View {
        let hasSnapshot = thumbnail != nil
        return Group {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    )
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            }
        }
        .overlay(alignment: hasSnapshot ? .bottomTrailing : .center) {
            appIcon(size: hasSnapshot ? iconSize : min(boxSize.width, boxSize.height) * 0.5)
                .shadow(color: .black.opacity(hasSnapshot ? 0.35 : 0), radius: 3, y: 1)
                .padding(hasSnapshot ? 4 : 0)
        }
    }

    /// The app's icon with its Dock-style notification badge straddling the
    /// icon's top-trailing corner, playing the "Icon reaction" on selection.
    private func appIcon(size: CGFloat) -> some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
            } else {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .topTrailing) {
            if showBadges, let badge, !badge.isEmpty {
                Text(badge)
                    .font(.system(size: badgeSize, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3 * scale)
                    .padding(.vertical, 0.5 * scale)
                    .background(Capsule().fill(.red))
                    .fixedSize()
                    .alignmentGuide(.top) { $0[VerticalAlignment.center] }
                    .alignmentGuide(.trailing) { $0[HorizontalAlignment.center] }
            }
        }
        // Same whimsy as the list: the icon reacts as its tile is selected.
        .iconReaction(isSelected: isSelected)
    }
}
