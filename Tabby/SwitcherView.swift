import SwiftUI

struct SwitcherView: View {
    @ObservedObject var controller: SwitcherController
    @AppStorage(SettingsKey.showAppName) private var showAppName = true

    private let iconSize: CGFloat = 26
    private let spacing: CGFloat = 4
    private let previewHeight: CGFloat = 200
    private let scrollSpace = "switcherScroll"

    /// Y positions of the content's top and bottom edges within the scroll
    /// viewport (0...maxColumnHeight). Used to decide whether rows extend past
    /// the visible area in each direction, so we can show scroll chevrons.
    @State private var topEdgeY: CGFloat = 0
    @State private var bottomEdgeY: CGFloat = 0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: spacing) {
                    ForEach(Array(controller.windows.enumerated()), id: \.element.id) { index, window in
                        VStack(spacing: spacing) {
                            WindowRow(
                                window: window,
                                icon: controller.icons[window.pid],
                                badge: controller.badges[window.pid],
                                isSelected: index == controller.selectedIndex,
                                iconSize: iconSize,
                                nameWidth: nameColumnWidth
                            )

                            // Live window preview, revealed inline under the row
                            // once the user has dwelled on it (Cmd held ~2s).
                            if let image = previewImage(for: window) {
                                preview(image)
                            }
                        }
                        .id(window.id)
                    }
                }
                .padding(12)
                .overlay(alignment: .top) {
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: TopEdgeKey.self,
                            value: geo.frame(in: .named(scrollSpace)).minY
                        )
                    }
                    .frame(height: 0)
                }
                .overlay(alignment: .bottom) {
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: BottomEdgeKey.self,
                            value: geo.frame(in: .named(scrollSpace)).minY
                        )
                    }
                    .frame(height: 0)
                }
            }
            .coordinateSpace(name: scrollSpace)
            .frame(height: maxColumnHeight)
            .onPreferenceChange(TopEdgeKey.self) { topEdgeY = $0 }
            .onPreferenceChange(BottomEdgeKey.self) { bottomEdgeY = $0 }
            .overlay(alignment: .top) {
                if canScrollUp { scrollChevron(up: true) }
            }
            .overlay(alignment: .bottom) {
                if canScrollDown { scrollChevron(up: false) }
            }
            .onChange(of: controller.selectedIndex) { newValue in
                guard controller.windows.indices.contains(newValue) else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(controller.windows[newValue].id, anchor: .center)
                }
            }
            .onChange(of: controller.previewWindowID) { newValue in
                guard let id = newValue else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
        .background(
            VisualEffectBackground(
                material: .underWindowBackground,
                blendingMode: .behindWindow,
                cornerRadius: 20
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .fixedSize()
    }

    /// Whether rows extend above the visible area (something scrolled off the top):
    /// the content's top edge sits above the viewport's top (y = 0).
    private var canScrollUp: Bool {
        topEdgeY < -1
    }

    /// Whether rows extend below the visible area (something scrolled off the
    /// bottom): the content's bottom edge sits below the viewport's bottom.
    private var canScrollDown: Bool {
        bottomEdgeY - maxColumnHeight > 1
    }

    /// A chevron fading in at the top or bottom edge to signal more rows in that
    /// direction. Non-interactive so it doesn't block the list.
    private func scrollChevron(up: Bool) -> some View {
        ZStack {
            LinearGradient(
                colors: [Color(nsColor: .windowBackgroundColor).opacity(0.95), .clear],
                startPoint: up ? .top : .bottom,
                endPoint: up ? .bottom : .top
            )
            Image(systemName: up ? "chevron.compact.up" : "chevron.compact.down")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(.secondary)
                .frame(maxHeight: .infinity, alignment: up ? .top : .bottom)
                .padding(up ? .top : .bottom, 2)
        }
        .frame(height: 26)
        .allowsHitTesting(false)
    }

    /// The captured window image to show under `window`, or nil when it isn't the
    /// dwelled-on selection (or no thumbnail is available).
    private func previewImage(for window: WindowInfo) -> NSImage? {
        guard controller.previewWindowID == window.id else { return nil }
        return controller.thumbnails[window.id]
    }

    /// A live window snapshot, letterboxed into the list's width so the HUD only
    /// grows downward when it appears — the left and right edges never move.
    private func preview(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: rowContentWidth, height: previewHeight)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .padding(.top, 2)
            .padding(.bottom, 4)
    }

    private var maxColumnHeight: CGFloat {
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 900
        let rowHeight = iconSize + 8
        var naturalHeight = CGFloat(controller.windows.count) * (rowHeight + spacing) + spacing + 24
        // Reserve room for the inline preview so the panel grows to fit it.
        if previewVisible {
            naturalHeight += previewHeight + spacing + 6
        }
        return min(naturalHeight, screenHeight * 0.85)
    }

    /// True when a dwell preview is currently showing (an image exists for it).
    private var previewVisible: Bool {
        guard let id = controller.previewWindowID else { return false }
        return controller.thumbnails[id] != nil
    }

    /// Width of a row's content (icon + gap + name column + row padding). The
    /// inline preview is sized to this so the HUD's width never changes.
    private var rowContentWidth: CGFloat {
        iconSize + 8 + nameColumnWidth + 16
    }

    /// Width of the name column, sized to the longest label so nothing is
    /// truncated, but capped at half the screen width for extreme titles.
    private var nameColumnWidth: CGFloat {
        let font = NSFont.preferredFont(forTextStyle: .body)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]

        let widest = controller.windows.reduce(CGFloat(0)) { widest, window in
            let name = switcherDisplayName(for: window, showAppName: showAppName)
            let width = (name as NSString).size(withAttributes: attributes).width
            return max(widest, width)
        }

        let screenWidth = NSScreen.main?.visibleFrame.width ?? 1200
        // +2 guards against sub-pixel rounding that would clip the last glyph.
        return min(max(widest.rounded(.up) + 2, 80), screenWidth * 0.5)
    }
}

/// Builds a window's row label: "AppName — Window Title", reducing multi-segment
/// titles (e.g. Safari's "Profile — Page") to their last em-dash segment and
/// respecting the "Show app name" setting. Shared so the layout can measure the
/// same string the row renders.
func switcherDisplayName(for window: WindowInfo, showAppName: Bool) -> String {
    let app = window.ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
    let rawTitle = window.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let title = rawTitle
        .components(separatedBy: "—")
        .last?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? rawTitle

    guard showAppName else {
        return title.isEmpty ? app : title
    }

    switch (app.isEmpty, title.isEmpty) {
    case (false, false): return "\(app) — \(title)"
    case (false, true): return app
    case (true, false): return title
    case (true, true): return ""
    }
}

private struct WindowRow: View {
    let window: WindowInfo
    let icon: NSImage?
    let badge: String?
    let isSelected: Bool
    let iconSize: CGFloat
    let nameWidth: CGFloat

    @AppStorage(SettingsKey.showAppName) private var showAppName = true

    private var displayName: String {
        switcherDisplayName(for: window, showAppName: showAppName)
    }

    /// Hidden apps are shown grayed out. Minimized windows are shown normally.
    private var isDimmed: Bool {
        window.isHidden
    }

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                } else {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                }
            }
            .frame(width: iconSize, height: iconSize)
            .saturation(isDimmed ? 0 : 1)
            .opacity(isDimmed ? 0.5 : 1)
            .overlay(alignment: .topTrailing) {
                if let badge, !badge.isEmpty {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(.red))
                        .fixedSize()
                        .offset(x: 6, y: -5)
                }
            }

            Text(displayName)
                .font(.body)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(Color.black)
                .frame(width: nameWidth, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.35) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
        )
    }
}

/// A transparent, Dock-like backdrop. Uses `NSVisualEffectView` with
/// `behindWindow` blending so it blurs the desktop and windows *behind* the
/// panel (SwiftUI materials and `glassEffect` only composite an opaque slab in
/// a borderless panel). Corners are rounded at the layer level so the material
/// clips cleanly.
private struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    var cornerRadius: CGFloat = 0

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = false
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.layer?.cornerRadius = cornerRadius
    }
}

/// Y position of the switcher content's top edge within the scroll viewport.
private struct TopEdgeKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Y position of the switcher content's bottom edge within the scroll viewport.
private struct BottomEdgeKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
