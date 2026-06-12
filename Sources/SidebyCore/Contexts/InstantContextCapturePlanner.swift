import Foundation

public struct InstantCaptureDisplay: Equatable, Sendable {
    public let displayID: String
    public let spaceCount: Int
    /// 0-based index of the display's current Space.
    public let currentSpaceIndex: Int

    public init(displayID: String, spaceCount: Int, currentSpaceIndex: Int) {
        self.displayID = displayID
        self.spaceCount = spaceCount
        self.currentSpaceIndex = currentSpaceIndex
    }
}

public struct InstantCapturePlan: Equatable, Sendable {
    public let contexts: [ContextDefinition]
    public let currentContextID: String
    public let captureLimit: Int
    /// True when every display reports the same current Space index.
    public let isSynchronized: Bool

    public init(
        contexts: [ContextDefinition],
        currentContextID: String,
        captureLimit: Int,
        isSynchronized: Bool
    ) {
        self.contexts = contexts
        self.currentContextID = currentContextID
        self.captureLimit = captureLimit
        self.isSynchronized = isSynchronized
    }
}

public enum InstantContextCapturePlanner {
    public static let maxContexts = 12

    public static func plan(for displays: [InstantCaptureDisplay]) -> InstantCapturePlan? {
        guard !displays.isEmpty,
              displays.allSatisfy({ $0.spaceCount >= 1 })
        else {
            return nil
        }

        let contextCount = min(
            displays.map(\.spaceCount).max() ?? 1,
            Self.maxContexts
        )
        let contexts = (1...contextCount).map { order in
            ContextDefinition(
                id: "context-\(order)",
                order: order,
                name: "Context \(order)",
                displayIDs: displays
                    .filter { $0.spaceCount >= order }
                    .map(\.displayID)
            )
        }

        let firstIndex = displays[0].currentSpaceIndex
        let currentOrder = min(max(firstIndex + 1, 1), contextCount)
        let isSynchronized = displays
            .allSatisfy { $0.currentSpaceIndex == firstIndex }

        return InstantCapturePlan(
            contexts: contexts,
            currentContextID: "context-\(currentOrder)",
            captureLimit: contextCount,
            isSynchronized: isSynchronized
        )
    }
}
