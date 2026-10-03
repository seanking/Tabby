import SwiftUI

/// Fixed measurements of the floating preview card, shared by the layout math
/// (which sizes and places the card's panel) and the view that draws it.
enum PreviewCardMetrics {
    /// Inset between the card's edge and the snapshot/caption.
    static let padding: CGFloat = 10
    static let cornerRadius: CGFloat = 16
    static let captionHeight: CGFloat = 20
    static let captionSpacing: CGFloat = 8
    /// How far the notch pointing at the selected row sticks out of the card.
    static let notchDepth: CGFloat = 8
    /// Height of the notch where it meets the card.
    static let notchWidth: CGFloat = 18
    /// Space between the HUD's edge and the notch's tip.
    static let gap: CGFloat = 6
    /// Narrowest the content may get, so the caption stays readable for tall,
    /// thin windows and when there's little room beside the HUD.
    static let minContentWidth: CGFloat = 160
}

/// Where the preview card goes and how it's drawn.
struct PreviewCardLayout: Equatable {
    /// The card panel's frame in screen coordinates, notch included.
    var frame: CGRect
    /// The side of the card the notch is on: `.leading` when the card sits to
    /// the right of the HUD (pointing back left at it), `.trailing` otherwise.
    var notchEdge: HorizontalEdge
    /// The notch's vertical center, measured down from the card's top edge.
    var notchY: CGFloat
    /// The snapshot's on-screen size: the window's aspect ratio fitted into the
    /// Preview "Size" box, so there are no letterbox bars.
    var imageSize: CGSize
}

/// Places the preview card beside the HUD without moving or resizing the HUD.
/// The card goes on whichever side has more room, shrinks to fit that room if
/// needed, and is vertically centered on `anchorY` (the selected row's middle,
/// in screen coordinates) while staying on screen. The notch tracks the row
/// even when clamping pushes the card up or down. A free function so the layout
/// can be tested without building a window.
func previewCardLayout(
    imageSize: CGSize,
    maxImageSize: CGSize,
    hudFrame: CGRect,
    anchorY: CGFloat,
    visibleFrame: CGRect
) -> PreviewCardLayout {
    let m = PreviewCardMetrics.self
    let chromeWidth = m.padding * 2 + m.notchDepth
    let chromeHeight = m.padding * 2 + m.captionSpacing + m.captionHeight

    let roomRight = visibleFrame.maxX - hudFrame.maxX - m.gap
    let roomLeft = hudFrame.minX - visibleFrame.minX - m.gap
    let onRight = roomRight >= roomLeft
    let room = max(onRight ? roomRight : roomLeft, 0)

    // Fit the snapshot inside the Size box, the room beside the HUD, and the
    // screen's height, keeping the window's own aspect ratio.
    let box = CGSize(
        width: max(min(maxImageSize.width, room - chromeWidth), m.minContentWidth),
        height: max(min(maxImageSize.height, visibleFrame.height - chromeHeight), 1)
    )
    let fitted = aspectFit(imageSize, in: box)
    let size = CGSize(
        width: max(fitted.width, m.minContentWidth) + chromeWidth,
        height: fitted.height + chromeHeight
    )

    // Beside the HUD, but never off screen (a cramped display may force the
    // minimum width to overlap the HUD rather than run off the edge).
    var x = onRight ? hudFrame.maxX + m.gap : hudFrame.minX - m.gap - size.width
    x = min(max(x, visibleFrame.minX), visibleFrame.maxX - size.width)

    // Point at the row, but only within the HUD, so a row scrolled out of view
    // doesn't pull the card away from the switcher.
    let inset = m.cornerRadius + m.notchWidth / 2
    let anchor = min(max(anchorY, hudFrame.minY + inset), hudFrame.maxY - inset)
    var y = anchor - size.height / 2
    y = min(max(y, visibleFrame.minY), visibleFrame.maxY - size.height)

    let frame = CGRect(x: x, y: y, width: size.width, height: size.height).integral
    let notchY = min(max(frame.maxY - anchor, inset), frame.height - inset)

    return PreviewCardLayout(
        frame: frame,
        notchEdge: onRight ? .leading : .trailing,
        notchY: notchY,
        imageSize: fitted
    )
}

/// Scales `size` to the largest size with the same aspect ratio that fits in
/// `box`, rounded to whole points.
private func aspectFit(_ size: CGSize, in box: CGSize) -> CGSize {
    guard size.width > 0, size.height > 0 else { return box }
    let scale = min(box.width / size.width, box.height / size.height)
    return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
}

/// The card's outline: a rounded rectangle with a small notch on one side,
/// pointing at the selected row in the HUD.
struct PreviewCardShape: Shape {
    var notchEdge: HorizontalEdge
    var notchY: CGFloat

    func path(in rect: CGRect) -> Path {
        let m = PreviewCardMetrics.self
        var body = rect
        body.size.width -= m.notchDepth
        if notchEdge == .leading { body.origin.x += m.notchDepth }

        // The notch's base reaches 1pt into the body so the union has no seam.
        let half = m.notchWidth / 2
        let baseX = notchEdge == .leading ? body.minX + 1 : body.maxX - 1
        let tipX = notchEdge == .leading ? rect.minX : rect.maxX
        var notch = Path()
        notch.move(to: CGPoint(x: baseX, y: notchY - half))
        notch.addLine(to: CGPoint(x: tipX, y: notchY))
        notch.addLine(to: CGPoint(x: baseX, y: notchY + half))
        notch.closeSubpath()

        return Path(roundedRect: body, cornerRadius: m.cornerRadius, style: .continuous)
            .union(notch)
    }
}

/// The floating preview card: the selected window's snapshot with a caption
/// (app icon, window title, and whether it's minimized or hidden). Shown in
/// its own panel beside the HUD so the switcher never changes shape. Clicking
/// it switches to the window.
struct PreviewCardView: View {
    @ObservedObject var controller: SwitcherController

    var body: some View {
        if let card = controller.previewCard,
           let id = controller.previewWindowID,
           let image = controller.thumbnails[id],
           let window = controller.windows.first(where: { $0.id == id }) {
            let shape = PreviewCardShape(notchEdge: card.notchEdge, notchY: card.notchY)
            VStack(spacing: PreviewCardMetrics.captionSpacing) {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: card.imageSize.width, height: card.imageSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                caption(for: window)
            }
            .padding(PreviewCardMetrics.padding)
            // Keep the content clear of the notch.
            .padding(card.notchEdge == .leading ? .leading : .trailing, PreviewCardMetrics.notchDepth)
            .frame(width: card.frame.width, height: card.frame.height)
            .background(
                VisualEffectBackground(
                    material: .underWindowBackground,
                    blendingMode: .behindWindow,
                    maskImage: maskImage(for: shape, size: card.frame.size)
                )
            )
            .overlay(shape.stroke(Color.primary.opacity(0.12), lineWidth: 1))
            .contentShape(shape)
            .onTapGesture {
                controller.choosePreviewed()
            }
        }
    }

    private func caption(for window: WindowInfo) -> some View {
        HStack(spacing: 6) {
            if let icon = controller.icons[window.pid] {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
            }
            Text(switcherDisplayName(for: window, showAppName: false))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if let status = status(of: window) {
                Text(status)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
        .font(.callout)
        .frame(height: PreviewCardMetrics.captionHeight)
    }

    /// Hidden/minimized windows can't be captured live, so the snapshot may be
    /// stale; say so rather than presenting it as the window's current state.
    private func status(of window: WindowInfo) -> String? {
        if window.isMinimized { return "Minimized" }
        if window.isHidden { return "Hidden" }
        return nil
    }

    /// The card's outline rendered as an image, for `NSVisualEffectView`'s mask:
    /// a SwiftUI clip can't shape a behind-window material, but a mask image can.
    private func maskImage(for shape: PreviewCardShape, size: CGSize) -> NSImage {
        NSImage(size: size, flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.addPath(shape.path(in: rect).cgPath)
            context.setFillColor(.black)
            context.fillPath()
            return true
        }
    }
}
