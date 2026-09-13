import Foundation
import SidebyCore

/// Presentation only: preserves stored order and remembered values without observing or moving Spaces.
struct WorkspaceTablePresentation {
    let sidebarWidth: CGFloat
    let inset: CGFloat
    let contentWidth: CGFloat
    let nameWidth: CGFloat
    let displayWidth: CGFloat

    init(windowWidth: CGFloat, displayCount: Int) {
        sidebarWidth = windowWidth < 780 ? 136 : 148
        inset = windowWidth < 780 ? 16 : 20
        contentWidth = windowWidth - sidebarWidth - 1 - inset * 2
        nameWidth = windowWidth < 780 ? 184 : 200
        displayWidth = displayCount == 2 ? min(180, max(160, (contentWidth - nameWidth) / 2)) : 160
    }

    static func displayIDs(connected: [String], remembered: [String], assigned: [String], order: [String],
                           includeDisconnected: Bool = false) -> [String] {
        let available = Set(includeDisconnected ? connected + remembered + assigned : connected)
        var seen = Set<String>()
        return (order + connected + available.sorted()).filter { available.contains($0) && seen.insert($0).inserted }
    }

    enum AssignmentState: Equatable { case assigned, unassigned, offline, excluded, unavailable, invalid }
    static func state(index: Int?, connected: Bool, selected: Bool, count: Int?) -> AssignmentState {
        guard connected else { return .offline }
        guard selected else { return .excluded }
        guard let count else { return .unavailable }
        guard let index else { return .unassigned }
        return index < 0 || index >= count ? .invalid : .assigned
    }

    static func hasGeometry(_ displays: [DisplayInfo]) -> Bool {
        !displays.isEmpty && displays.allSatisfy {
            guard let frame = $0.frame else { return false }
            return frame.x.isFinite && frame.y.isFinite && frame.width.isFinite && frame.height.isFinite
                && frame.width > 0 && frame.height > 0
        }
    }
}
