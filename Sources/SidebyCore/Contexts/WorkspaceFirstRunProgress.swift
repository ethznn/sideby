/// Durable guide progress containing task references, never private Space identities.
public struct WorkspaceFirstRunProgress: Equatable, Codable, Sendable {
    public private(set) var originContextID: String?
    public private(set) var awayContextID: String?
    public private(set) var isComplete = false

    public init() {}

    /// Start this sequence with a genuine verified named activation.
    /// Capture, internal alignment, failed and cancelled requests must not call this method.
    public mutating func recordSuccessfulVisit(contextID: String) {
        guard !isComplete, !contextID.isEmpty else { return }
        guard let originContextID else {
            self.originContextID = contextID
            return
        }
        if contextID != originContextID {
            if awayContextID == nil {
                awayContextID = contextID
            }
        } else if awayContextID != nil {
            isComplete = true
        }
    }

    /// A deleted task invalidates the saved exercise; future verified visits can restart it.
    public mutating func reconcile(validContextIDs: Set<String>) {
        let referencedContextIDs = [originContextID, awayContextID].compactMap { $0 }
        guard referencedContextIDs.allSatisfy(validContextIDs.contains) else {
            self = WorkspaceFirstRunProgress()
            return
        }
    }
}
