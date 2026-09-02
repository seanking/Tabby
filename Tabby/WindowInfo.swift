import CoreGraphics

struct WindowInfo: Identifiable, Equatable {
    let id: CGWindowID
    let pid: pid_t
    let ownerName: String
    let title: String
    let bounds: CGRect
    /// True when the owning app is hidden (e.g. via Cmd+H). Such windows are
    /// still listed, but shown grayed out.
    var isHidden: Bool = false
    /// True when the window itself is minimized (in the Dock). Listed but grayed
    /// out; selecting it restores the window.
    var isMinimized: Bool = false

    static func == (lhs: WindowInfo, rhs: WindowInfo) -> Bool {
        lhs.id == rhs.id
    }
}
