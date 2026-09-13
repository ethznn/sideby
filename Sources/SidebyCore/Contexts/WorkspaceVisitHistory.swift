/// Runtime history of verified named activations, independent of capture or live matching.
public struct WorkspaceVisitHistory: Equatable, Sendable {
    public private(set) var currentContextID: String?
    public private(set) var previousContextID: String?

    public init() {}

    /// Call only after the target workspace has been verified successfully.
    public mutating func recordSuccessfulVisit(contextID: String) {
        guard !contextID.isEmpty, contextID != currentContextID else { return }
        previousContextID = currentContextID
        currentContextID = contextID
    }

    public mutating func reconcile(validContextIDs: Set<String>) {
        if let currentContextID, !validContextIDs.contains(currentContextID) {
            self.currentContextID = nil
        }
        if let previousContextID, !validContextIDs.contains(previousContextID) {
            self.previousContextID = nil
        }
    }
}
