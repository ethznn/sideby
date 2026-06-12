import Foundation

public struct DisplaySpaceLayout: Equatable, Sendable {
    public let displayUUID: String
    public let spaceIDs: [UInt64]
    public let currentSpaceID: UInt64

    public init(displayUUID: String, spaceIDs: [UInt64], currentSpaceID: UInt64) {
        self.displayUUID = displayUUID
        self.spaceIDs = spaceIDs
        self.currentSpaceID = currentSpaceID
    }

    /// Parses the bridged payload of SLSCopyManagedDisplaySpaces. Returns nil
    /// if any entry is malformed — never a partial layout.
    public static func displays(
        fromManagedDisplaySpaces payload: [[String: Any]]
    ) -> [DisplaySpaceLayout]? {
        var layouts: [DisplaySpaceLayout] = []
        for entry in payload {
            guard
                let uuid = entry["Display Identifier"] as? String,
                let current = entry["Current Space"] as? [String: Any],
                let currentID = (current["ManagedSpaceID"] as? NSNumber)?.uint64Value,
                let spaces = entry["Spaces"] as? [[String: Any]],
                !spaces.isEmpty
            else {
                return nil
            }

            var spaceIDs: [UInt64] = []
            for space in spaces {
                guard let id = (space["ManagedSpaceID"] as? NSNumber)?.uint64Value else {
                    return nil
                }
                spaceIDs.append(id)
            }
            layouts.append(
                DisplaySpaceLayout(
                    displayUUID: uuid,
                    spaceIDs: spaceIDs,
                    currentSpaceID: currentID
                )
            )
        }
        return layouts
    }
}

public protocol SpaceLayoutReading: Sendable {
    /// Returns the per-display Space layout, or nil when unavailable.
    func readLayout() -> [DisplaySpaceLayout]?
}
