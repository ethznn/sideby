public enum WorkspaceConnectionStatus: Equatable, Sendable {
    case ready
    case unconfirmed
    case changed(Set<String>)
    case unavailable(Set<String>)
}

/// An explicit connection baseline valid only for this app session.
/// Private Space identities remain transient; this type must not be persisted.
public struct WorkspaceConnectionSession: Equatable, Sendable {
    private var confirmedSpaceIDsByDisplayID: [String: [UInt64]]?

    public init() {}

    /// Replaces the baseline only when every supplied layout is usable.
    /// A failed confirmation discards previous trust so stale mappings stay blocked.
    @discardableResult
    public mutating func confirm(spaceIDsByDisplayID: [String: [UInt64]]) -> Bool {
        reset()
        guard !spaceIDsByDisplayID.isEmpty,
              Self.unavailableDisplayIDs(
                for: Set(spaceIDsByDisplayID.keys),
                in: spaceIDsByDisplayID
              ).isEmpty
        else {
            return false
        }
        confirmedSpaceIDsByDisplayID = spaceIDsByDisplayID
        return true
    }

    public func status(
        for displayIDs: Set<String>,
        spaceIDsByDisplayID: [String: [UInt64]]?
    ) -> WorkspaceConnectionStatus {
        guard !displayIDs.isEmpty else {
            return .unavailable([])
        }
        guard let confirmedSpaceIDsByDisplayID,
              displayIDs.isSubset(of: Set(confirmedSpaceIDsByDisplayID.keys))
        else {
            return .unconfirmed
        }
        guard let spaceIDsByDisplayID else {
            return .unavailable(displayIDs)
        }

        let unavailableDisplayIDs = Self.unavailableDisplayIDs(for: displayIDs, in: spaceIDsByDisplayID)
        guard unavailableDisplayIDs.isEmpty else {
            return .unavailable(unavailableDisplayIDs)
        }

        let changedDisplayIDs = displayIDs.filter {
            spaceIDsByDisplayID[$0] != confirmedSpaceIDsByDisplayID[$0]
        }
        return changedDisplayIDs.isEmpty ? .ready : .changed(changedDisplayIDs)
    }

    public mutating func reset() {
        confirmedSpaceIDsByDisplayID = nil
    }

    private static func unavailableDisplayIDs(
        for displayIDs: Set<String>,
        in layouts: [String: [UInt64]]
    ) -> Set<String> {
        var unavailableDisplayIDs = Set<String>()
        var displayIDBySpaceID: [UInt64: String] = [:]

        for displayID in displayIDs {
            guard !displayID.isEmpty, let spaceIDs = layouts[displayID], !spaceIDs.isEmpty else {
                unavailableDisplayIDs.insert(displayID)
                continue
            }
            let uniqueSpaceIDs = Set(spaceIDs)
            if uniqueSpaceIDs.count != spaceIDs.count {
                unavailableDisplayIDs.insert(displayID)
            }
            for spaceID in uniqueSpaceIDs {
                if let otherDisplayID = displayIDBySpaceID[spaceID] {
                    // Shared identity cannot establish independent display layouts.
                    unavailableDisplayIDs.formUnion([displayID, otherDisplayID])
                } else {
                    displayIDBySpaceID[spaceID] = displayID
                }
            }
        }
        return unavailableDisplayIDs
    }
}
