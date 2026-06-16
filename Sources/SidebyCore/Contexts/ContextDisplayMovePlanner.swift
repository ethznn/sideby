public struct ContextDisplayMove: Equatable, Sendable {
    public let displayID: String
    public let currentIndex: Int
    public let targetIndex: Int

    public init(displayID: String, currentIndex: Int, targetIndex: Int) {
        self.displayID = displayID
        self.currentIndex = currentIndex
        self.targetIndex = targetIndex
    }
}

public enum ContextDisplayMovePlanner: Sendable {
    public static func moves(
        displays: [InstantCaptureDisplay],
        targetContext: ContextDefinition
    ) -> [ContextDisplayMove] {
        displays.compactMap { display in
            guard let targetIndex = targetContext.spaceIndex(for: display.displayID),
                  display.currentSpaceIndex != targetIndex
            else {
                return nil
            }
            return ContextDisplayMove(
                displayID: display.displayID,
                currentIndex: display.currentSpaceIndex,
                targetIndex: targetIndex
            )
        }
    }
}
