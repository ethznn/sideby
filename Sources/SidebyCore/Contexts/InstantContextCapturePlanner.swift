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
        let maxCurrentIndex = displays.map(\.currentSpaceIndex).max() ?? 0
        let currentOrder = min(maxCurrentIndex + 1, contextCount)
        let indexesByDisplay = Dictionary(
            uniqueKeysWithValues: displays.map {
                ($0.displayID, displaySpaceIndexesByContextOrder(
                    for: $0,
                    currentOrder: currentOrder,
                    contextCount: contextCount
                ))
            }
        )
        let contexts = (1...contextCount).map { order in
            let displaySpaceIndexes = Dictionary(
                uniqueKeysWithValues: displays.compactMap { display in
                    indexesByDisplay[display.displayID]?[order].map {
                        (display.displayID, $0)
                    }
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

        let currentContext = contexts.first { $0.order == currentOrder }
        let isSynchronized = displays.allSatisfy { display in
            currentContext?.spaceIndex(for: display.displayID) == display.currentSpaceIndex
        }

        return InstantCapturePlan(
            contexts: contexts,
            currentContextID: "context-\(currentOrder)",
            isSynchronized: isSynchronized
        )
    }

    private static func displaySpaceIndexesByContextOrder(
        for display: InstantCaptureDisplay,
        currentOrder: Int,
        contextCount: Int
    ) -> [Int: Int] {
        guard display.currentSpaceIndex < contextCount else {
            return Dictionary(
                uniqueKeysWithValues: (0..<min(display.spaceCount, contextCount)).map { ($0 + 1, $0) }
            )
        }

        var indexesByOrder: [Int: Int] = [:]
        for spaceIndex in 0..<display.spaceCount {
            let order = spaceIndex < display.currentSpaceIndex
                ? spaceIndex + 1
                : currentOrder + (spaceIndex - display.currentSpaceIndex)
            guard order >= 1, order <= contextCount else {
                continue
            }
            indexesByOrder[order] = spaceIndex
        }
        return indexesByOrder
    }
}
