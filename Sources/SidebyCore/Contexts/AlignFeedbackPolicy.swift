public enum AlignFeedbackReason: Equatable, Sendable {
    case alreadyAligned
    case notInContext
}

public struct AlignDisplayFeedback: Equatable, Sendable {
    public let displayID: String
    public let reason: AlignFeedbackReason

    public init(displayID: String, reason: AlignFeedbackReason) {
        self.displayID = displayID
        self.reason = reason
    }
}

// Classifies the displays that an align pass leaves in place so the app can
// explain on-screen why nothing moved. This is the complement of the move
// filter in alignDisplaysToCurrentSpace: a display that would be moved (a
// target-context member not yet at the target space) produces no feedback.
public enum AlignFeedbackPolicy: Sendable {
    public static func feedback(
        displays: [InstantCaptureDisplay],
        referenceDisplayID: String,
        targetContext: ContextDefinition
    ) -> [AlignDisplayFeedback] {
        let members = Set(targetContext.displayIDs)

        return displays.compactMap { display in
            guard display.displayID != referenceDisplayID else {
                return nil
            }

            guard members.contains(display.displayID) else {
                return AlignDisplayFeedback(displayID: display.displayID, reason: .notInContext)
            }

            guard let targetIndex = targetContext.spaceIndex(for: display.displayID) else {
                return AlignDisplayFeedback(displayID: display.displayID, reason: .notInContext)
            }

            guard display.currentSpaceIndex == targetIndex else {
                return nil
            }

            return AlignDisplayFeedback(displayID: display.displayID, reason: .alreadyAligned)
        }
    }
}
