import SidebyCore
import SidebySystem

/// Current positions and ordered identities from one read of macOS Spaces.
/// This is deliberately not Codable; private identities never leave memory.
struct WorkspaceLayoutObservation: Equatable, Sendable {
    let displays: [InstantCaptureDisplay]
    let spaceIDsByDisplayID: [String: [UInt64]]

    static func make(
        layouts: [DisplaySpaceLayout], snapshots: [DisplaySnapshot], selectedDisplayIDs: Set<String>,
        isInteractiveSession: Bool = true
    ) -> WorkspaceLayoutObservation? {
        guard isInteractiveSession else { return nil }
        let mapping = DisplayLayoutMapper.stableIDsByUUID(
            snapshots: snapshots, uuidForDisplayID: { _ in nil }
        )
        var identities: [String: [UInt64]] = [:]
        var displays: [InstantCaptureDisplay] = []
        for layout in layouts {
            guard let id = mapping[layout.displayUUID], selectedDisplayIDs.contains(id) else { continue }
            guard identities[id] == nil, !layout.spaceIDs.isEmpty,
                  Set(layout.spaceIDs).count == layout.spaceIDs.count,
                  let currentIndex = layout.spaceIDs.firstIndex(of: layout.currentSpaceID) else { return nil }
            identities[id] = layout.spaceIDs
            displays.append(.init(displayID: id, spaceCount: layout.spaceIDs.count, currentSpaceIndex: currentIndex))
        }
        let order = snapshots.map { DisplayLayoutMapper.stableID(for: $0) }
        displays.sort { (order.firstIndex(of: $0.displayID) ?? .max) < (order.firstIndex(of: $1.displayID) ?? .max) }
        return displays.isEmpty ? nil : .init(displays: displays, spaceIDsByDisplayID: identities)
    }
}
