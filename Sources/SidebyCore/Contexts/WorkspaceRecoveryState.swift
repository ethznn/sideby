/// Describes a fresh observation of the original target after an activation fails.
/// Execution remains the responsibility of the existing switching engine.
public struct WorkspaceRecoveryState: Equatable, Sendable {
    public let pendingDisplayIDs: Set<String>
    public let unavailableDisplayIDs: Set<String>
    public let invalidDisplayIDs: Set<String>
    public let alignedDisplayIDs: Set<String>

    public init(
        targetContext: ContextDefinition,
        selectedDisplayIDs: Set<String>,
        displays: [InstantCaptureDisplay]?
    ) {
        let requiredDisplayIDs = Set(targetContext.displayIDs).intersection(selectedDisplayIDs)
        let observationsByDisplayID = Dictionary(grouping: displays ?? [], by: \.displayID)
        var pendingDisplayIDs = Set<String>()
        var unavailableDisplayIDs = Set<String>()
        var invalidDisplayIDs = Set<String>()
        var alignedDisplayIDs = Set<String>()

        for displayID in requiredDisplayIDs {
            guard let observations = observationsByDisplayID[displayID],
                  observations.count == 1,
                  let display = observations.first,
                  display.spaceCount > 0,
                  display.currentSpaceIndex >= 0,
                  display.currentSpaceIndex < display.spaceCount
            else {
                unavailableDisplayIDs.insert(displayID)
                continue
            }
            guard let targetIndex = targetContext.spaceIndex(for: displayID),
                  targetIndex >= 0,
                  targetIndex < display.spaceCount
            else {
                invalidDisplayIDs.insert(displayID)
                continue
            }
            if display.currentSpaceIndex == targetIndex {
                alignedDisplayIDs.insert(displayID)
            } else {
                pendingDisplayIDs.insert(displayID)
            }
        }

        self.pendingDisplayIDs = pendingDisplayIDs
        self.unavailableDisplayIDs = unavailableDisplayIDs
        self.invalidDisplayIDs = invalidDisplayIDs
        self.alignedDisplayIDs = alignedDisplayIDs
    }

    public var canRetry: Bool {
        !pendingDisplayIDs.isEmpty && unavailableDisplayIDs.isEmpty && invalidDisplayIDs.isEmpty
    }

    public var isResolved: Bool {
        !alignedDisplayIDs.isEmpty && pendingDisplayIDs.isEmpty
            && unavailableDisplayIDs.isEmpty && invalidDisplayIDs.isEmpty
    }
}
