import SwiftUI

struct SwitcherView: View {
    @ObservedObject var controller: SwitcherController
    @AppStorage(SettingsKey.showAppName) private var showAppName = true
    @AppStorage(SettingsKey.uiScale) private var scale = SettingsKey.defaultScale
    @AppStorage(SettingsKey.previewScale) private var previewScale = SettingsKey.defaultPreviewScale

    /// Name-label point size and app-icon side length at the current scale, so
    /// the "Size" control grows the text and icons together. `fontSize` also
    /// drives row-height and name-column measurement below.
    private var fontSize: CGFloat { SettingsKey.baseFontSize * scale }
    private var iconSize: CGFloat { SettingsKey.baseIconSize * scale }

    private let spacing: CGFloat = 4
    private let scrollSpace = "switcherScroll"

    /// Y positions of the content's top and bottom edges within the scroll
    /// viewport (0...maxColumnHeight). Used to decide whether rows extend past
    /// the visible area in each direction, so we can show scroll chevrons.
    @State private var topEdgeY: CGFloat = 0
    @State private var bottomEdgeY: CGFloat = 0

    var body: some View {
        // The preview sits beside the list rather than under the selected row, so
        // it can be sized freely: the list keeps its natural width and the pane
        // extends the HUD to the right. Top-aligned so revealing a tall preview
        // grows the panel downward instead of shifting the list.
        HStack(alignment: .top, spacing: 0) {
            listColumn
            if let image = previewImage {
                preview(image)
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
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .fixedSize()
    }

    /// The window list itself: the filter field (when active) above a scrolling
    /// column of rows.
    private var listColumn: some View {
        VStack(spacing: 0) {
            if controller.filterActive {
                filterBar
            }
            ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: spacing) {
                    ForEach(Array(controller.windows.enumerated()), id: \.element.id) { index, window in
                        WindowRow(
                            window: window,
                            icon: controller.icons[window.pid],
                            badge: controller.badges[window.pid],
                            isSelected: index == controller.selectedIndex,
                            iconSize: iconSize,
                            nameWidth: nameColumnWidth
                        )
                        // Point the selection at whatever row the cursor is
                        // over, and commit to it on click. Continuous hover
                        // (rather than enter/exit) so the controller sees every
                        // pointer position and can tell a deliberate move —
                        // including one inside the row the cursor already rests
                        // in — from the HUD opening or reflowing underneath a
                        // still cursor.
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            if case .active = phase { controller.hover(index: index) }
                        }
                        .onTapGesture {
                            controller.choose(index: index)
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
            .onChange(of: controller.selectedIndex) { _, newValue in
                guard controller.autoScrollOnSelect else { return }
                guard controller.windows.indices.contains(newValue) else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(controller.windows[newValue].id, anchor: .center)
                }
            }
            .onChange(of: controller.previewWindowID) { _, newValue in
                guard let id = newValue else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
            }
        }
    }

    /// The filter field pinned above the list while Cmd+F filtering is active.
    /// Input is fed in through the event tap (the panel can't take key focus), so
    /// this only mirrors the current query rather than being an editable field.
    private var filterBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            Text(controller.filterText.isEmpty ? "Filter" : controller.filterText)
                .foregroundStyle(controller.filterText.isEmpty ? Color.secondary : Color.black)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 0)
        }
        .font(.body)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        // Match the rows' content width so the field aligns with them and a long
        // query truncates instead of widening the HUD.
        .frame(width: rowContentWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.08))
        )
        .padding(.horizontal, 12)
        .padding(.top, 12)
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

    /// The captured window image for the dwelled-on selection, or nil when no
    /// window is being previewed (or no thumbnail is available for it yet).
    private var previewImage: NSImage? {
        guard let id = controller.previewWindowID else { return nil }
        return controller.thumbnails[id]
    }

    /// A live window snapshot, letterboxed into the preview pane beside the list.
    /// The pane's size comes from the Preview "Size" setting alone, so it can be
    /// as large as the screen allows regardless of how wide the rows are.
    private func preview(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: previewSize.width, height: previewSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )
            // No leading padding: the list's own trailing padding already
            // provides the gutter between the rows and the pane.
            .padding(.trailing, 12)
            .padding(.vertical, 12)
    }

    /// The preview pane's box at the current "Size" setting.
    private var previewSize: CGSize {
        switcherPreviewSize(
            scale: previewScale,
            screenSize: NSScreen.main?.visibleFrame.size ?? CGSize(width: 1200, height: 900)
        )
    }

    private var maxColumnHeight: CGFloat {
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 900
        // A row is as tall as the larger of the icon and the (possibly enlarged)
        // name text, so the panel reserves enough height for big font sizes.
        let rowHeight = max(iconSize, (fontSize * 1.35).rounded(.up)) + 8
        let naturalHeight = CGFloat(controller.windows.count) * (rowHeight + spacing) + spacing + 24
        return min(naturalHeight, screenHeight * 0.85)
    }

    /// Width of a row's content (icon + gap + name column + row padding). The
    /// filter field is sized to this so it lines up with the rows.
    private var rowContentWidth: CGFloat {
        iconSize + 8 + nameColumnWidth + 16
    }

    /// Width of the name column, sized to the longest label so nothing is
    /// truncated, but capped at half the screen width for extreme titles.
    /// Measured against the full, unfiltered list so filtering can't change the
    /// HUD's width — narrowing the rows must never resize the panel horizontally.
    private var nameColumnWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]

        let widest = controller.allWindows.reduce(CGFloat(0)) { widest, window in
            let name = switcherDisplayName(for: window, showAppName: showAppName)
            let width = (name as NSString).size(withAttributes: attributes).width
            return max(widest, width)
        }

        let screenWidth = NSScreen.main?.visibleFrame.width ?? 1200
        // +2 guards against sub-pixel rounding that would clip the last glyph.
        return min(max(widest.rounded(.up) + 2, 80), screenWidth * 0.5)
    }
}

/// The size of the window preview pane at the Preview "Size" scale. The pane
/// sits beside the list, so its size is independent of the rows: 100% is the
/// baseline box and larger scales grow both dimensions together, keeping the
/// box's shape (and so the snapshot's letterboxing) the same at any size.
/// Capped to a fraction of the screen so an extreme scale can't push the HUD off
/// the display. A free function so the layout math can be tested without
/// building a view.
func switcherPreviewSize(scale: Double, screenSize: CGSize) -> CGSize {
    let range = SettingsKey.previewScaleRange
    let clamped = min(max(scale, range.lowerBound), range.upperBound)
    return CGSize(
        width: min(SettingsKey.basePreviewWidth * clamped, screenSize.width * 0.6),
        height: min(SettingsKey.basePreviewHeight * clamped, screenSize.height * 0.8)
    )
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
    @AppStorage(SettingsKey.showBadges) private var showBadges = true
    @AppStorage(SettingsKey.uiScale) private var scale = SettingsKey.defaultScale
    @AppStorage(SettingsKey.iconReaction) private var iconReaction: IconReaction = .none

    /// Bumped each time this row becomes the selection, driving the icon's
    /// reaction animation. A counter rather than a Bool so re-selecting the same
    /// row replays the animation and deselection never triggers one.
    @State private var reactionTrigger = 0

    /// Name-label and badge point sizes derived from the single "Size" scale, so
    /// one control grows the text, icons, and badges together.
    private var fontSize: CGFloat { SettingsKey.baseFontSize * scale }
    private var badgeSize: CGFloat { SettingsKey.baseBadgeSize * scale }

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
                if showBadges, let badge, !badge.isEmpty {
                    Text(badge)
                        .font(.system(size: badgeSize, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3 * scale)
                        .padding(.vertical, 0.5 * scale)
                        .background(Capsule().fill(.red))
                        .fixedSize()
                        // Center the badge on the icon's top-right corner, Dock-
                        // style, so it straddles the corner at any size and
                        // number width instead of floating beyond it.
                        .alignmentGuide(.top) { $0[VerticalAlignment.center] }
                        .alignmentGuide(.trailing) { $0[HorizontalAlignment.center] }
                }
            }
            // Whimsy: play the chosen reaction on the icon (and its badge) each
            // time this row becomes the selection.
            .keyframeAnimator(initialValue: IconReactionValues(), trigger: reactionTrigger) { view, value in
                view
                    .scaleEffect(x: value.scaleX, y: value.scaleY, anchor: .bottom)
                    .rotationEffect(.degrees(value.rotation))
                    .offset(y: value.offsetY)
            } keyframes: { _ in
                reactionKeyframes(for: iconReaction)
            }
            .onChange(of: isSelected) { _, selected in
                if selected { fireReaction() }
            }
            .onAppear {
                // The initially selected row reacts as the switcher opens.
                if isSelected { fireReaction() }
            }

            Text(displayName)
                .font(.system(size: fontSize))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(Color.primary)
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

    /// Replays the icon reaction, unless the user has turned reactions off.
    private func fireReaction() {
        guard iconReaction != .none else { return }
        reactionTrigger += 1
    }

    /// The keyframe timeline for a given reaction style. Every style shares the
    /// same four tracks so the timeline's type is fixed; each track animates only
    /// when its style is active and otherwise holds at rest. `.none` is never
    /// actually triggered (`fireReaction()` skips it), so all tracks stay at rest.
    @KeyframesBuilder<IconReactionValues>
    private func reactionKeyframes(for reaction: IconReaction) -> some Keyframes<IconReactionValues> {
        KeyframeTrack(\.offsetY) {
            if reaction == .bounce {
                SpringKeyframe(-9, duration: 0.18, spring: .snappy)
                SpringKeyframe(0, duration: 0.5, spring: .bouncy)
            } else {
                LinearKeyframe(0, duration: 0.01)
            }
        }
        KeyframeTrack(\.rotation) {
            if reaction == .wiggle {
                CubicKeyframe(-12, duration: 0.09)
                CubicKeyframe(12, duration: 0.12)
                CubicKeyframe(-8, duration: 0.12)
                CubicKeyframe(6, duration: 0.12)
                CubicKeyframe(0, duration: 0.1)
            } else {
                LinearKeyframe(0, duration: 0.01)
            }
        }
        KeyframeTrack(\.scaleY) {
            if reaction == .squashStretch {
                CubicKeyframe(0.7, duration: 0.12)
                CubicKeyframe(1.15, duration: 0.16)
                SpringKeyframe(1.0, duration: 0.34, spring: .bouncy)
            } else {
                LinearKeyframe(1.0, duration: 0.01)
            }
        }
        KeyframeTrack(\.scaleX) {
            if reaction == .squashStretch {
                CubicKeyframe(1.25, duration: 0.12)
                CubicKeyframe(0.9, duration: 0.16)
                SpringKeyframe(1.0, duration: 0.34, spring: .bouncy)
            } else {
                LinearKeyframe(1.0, duration: 0.01)
            }
        }
    }
}

/// The transform applied to a reacting icon. Not itself `Animatable` — the
/// keyframe tracks animate its individual `Animatable` properties (`CGFloat`
/// scale/offset and `Double` rotation), so each reaction style touches only the
/// tracks it cares about and leaves the rest at their resting values.
private struct IconReactionValues {
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1
    var rotation: Double = 0
    var offsetY: CGFloat = 0
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
