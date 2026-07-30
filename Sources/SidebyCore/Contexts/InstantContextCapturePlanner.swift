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
    /// True when every display reports the same current Space index.
    public let isSynchronized: Bool

    public init(
        contexts: [ContextDefinition],
        currentContextID: String,
        isSynchronized: Bool
    ) {
        self.contexts = contexts
        self.currentContextID = currentContextID
        self.isSynchronized = isSynchronized
    }

    public func contextsRenamingCurrentContext(to name: String) -> [ContextDefinition] {
        contexts.map { context in
            context.id == currentContextID ? context.renamed(name) : context
        }
    }

    public func contextsApplyingSuggestedCurrentName(_ name: String) -> [ContextDefinition] {
        guard isSynchronized else { return contexts }
        return contextsRenamingCurrentContext(to: name)
    }
}

public enum InstantContextCapturePlanner {
    /// Derives the context plan. The first display in `displays` is
    /// authoritative for the current context, so callers must pass displays
    /// in a stable, meaningful order (e.g. layout order).
    public static func plan(for displays: [InstantCaptureDisplay]) -> InstantCapturePlan? {
        guard !displays.isEmpty,
              displays.allSatisfy({ $0.spaceCount >= 1 && $0.currentSpaceIndex >= 0 && $0.currentSpaceIndex < $0.spaceCount })
        else {
            return nil
        }

        let contextCount = displays.map(\.spaceCount).max() ?? 1
        let currentOrder = displays[0].currentSpaceIndex + 1
        let contexts = (1...contextCount).map { order in
            let spaceIndex = order - 1
            let displaySpaceIndexes: [String: Int] = Dictionary(
                uniqueKeysWithValues: displays.compactMap { display in
                    guard spaceIndex < display.spaceCount else { return nil }
                    return (display.displayID, spaceIndex)
                }
            )
            return ContextDefinition(
                id: "context-\(order)",
                order: order,
                name: "Context \(order)",
                displayIDs: Array(displaySpaceIndexes.keys),
                displaySpaceIndexes: displaySpaceIndexes
            )
        }

        let referenceIndex = displays[0].currentSpaceIndex
        let isSynchronized = displays.allSatisfy { $0.currentSpaceIndex == referenceIndex }

        return InstantCapturePlan(
            contexts: contexts,
            currentContextID: "context-\(currentOrder)",
            isSynchronized: isSynchronized
        )
    }
}
