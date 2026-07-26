import Foundation

public enum ContextSyncState: String, Codable, Equatable, Sendable {
    case synchronized
    case needsSync

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = ContextSyncState(rawValue: rawValue) ?? .synchronized
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct ContextDefinition: Equatable, Codable, Identifiable, Sendable {
    public let id: String
    public private(set) var order: Int
    public private(set) var name: String
    public private(set) var displayIDs: [String]
    public private(set) var displaySpaceIndexes: [String: Int]

    private enum CodingKeys: String, CodingKey {
        case id
        case order
        case name
        case displayIDs
        case displaySpaceIndexes
    }

    public init(
        id: String,
        order: Int,
        name: String,
        displayIDs: [String] = [],
        displaySpaceIndexes: [String: Int]? = nil
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedOrder = max(order, 1)
        let normalizedSpaceIndexes = Self.normalizedDisplaySpaceIndexes(
            displayIDs: displayIDs,
            displaySpaceIndexes: displaySpaceIndexes,
            defaultSpaceIndex: normalizedOrder - 1
        )
        self.id = id
        self.order = normalizedOrder
        self.name = trimmedName.isEmpty
            ? "Context \(normalizedOrder)"
            : trimmedName
        self.displayIDs = normalizedSpaceIndexes.keys.sorted()
        self.displaySpaceIndexes = normalizedSpaceIndexes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            order: try container.decodeIfPresent(Int.self, forKey: .order) ?? 1,
            name: try container.decodeIfPresent(String.self, forKey: .name) ?? "",
            displayIDs: try container.decodeIfPresent([String].self, forKey: .displayIDs) ?? [],
            displaySpaceIndexes: try container.decodeIfPresent([String: Int].self, forKey: .displaySpaceIndexes)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(order, forKey: .order)
        try container.encode(name, forKey: .name)
        try container.encode(displayIDs, forKey: .displayIDs)
        if !usesDefaultSpaceIndexes {
            try container.encode(displaySpaceIndexes, forKey: .displaySpaceIndexes)
        }
    }

    public func spaceIndex(for displayID: String) -> Int? {
        displaySpaceIndexes[displayID]
    }

    public func renamed(_ name: String) -> ContextDefinition {
        ContextDefinition(
            id: id,
            order: order,
            name: name,
            displayIDs: displayIDs,
            displaySpaceIndexes: displaySpaceIndexes
        )
    }

    public var usesDefaultSpaceIndexes: Bool {
        displaySpaceIndexes == Self.defaultDisplaySpaceIndexes(
            displayIDs: displayIDs,
            defaultSpaceIndex: order - 1
        )
    }

    private static func normalizedDisplayIDs(_ displayIDs: [String]) -> [String] {
        var seen = Set<String>()
        return displayIDs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
            .filter { seen.insert($0).inserted }
    }

    private static func defaultDisplaySpaceIndexes(
        displayIDs: [String],
        defaultSpaceIndex: Int
    ) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: normalizedDisplayIDs(displayIDs).map { ($0, defaultSpaceIndex) })
    }

    private static func normalizedDisplaySpaceIndexes(
        displayIDs: [String],
        displaySpaceIndexes: [String: Int]?,
        defaultSpaceIndex: Int
    ) -> [String: Int] {
        var indexes = defaultDisplaySpaceIndexes(
            displayIDs: displayIDs,
            defaultSpaceIndex: max(defaultSpaceIndex, 0)
        )

        for (rawDisplayID, rawIndex) in displaySpaceIndexes ?? [:] {
            let displayID = rawDisplayID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !displayID.isEmpty, rawIndex >= 0 else {
                continue
            }
            indexes[displayID] = rawIndex
        }

        return indexes
    }
}

public struct ContextPlanNavigation: Equatable, Sendable {
    public let command: SwitchCommand
    public let targetContext: ContextDefinition?
    public let diagnostic: DiagnosticState?

    public var isAllowed: Bool {
        targetContext != nil
    }

    public init(command: SwitchCommand, targetContext: ContextDefinition?, diagnostic: DiagnosticState?) {
        self.command = command
        self.targetContext = targetContext
        self.diagnostic = diagnostic
    }
}

public struct ContextSwitchIntent: Equatable, Sendable {
    public let command: SwitchCommand
    public let targetContext: ContextDefinition?
    public let targetDisplayIDs: [String]
    public let diagnostic: DiagnosticState?
    public let shouldExecute: Bool

    public init(
        command: SwitchCommand,
        targetContext: ContextDefinition?,
        targetDisplayIDs: [String] = [],
        diagnostic: DiagnosticState?,
        shouldExecute: Bool
    ) {
        self.command = command
        self.targetContext = targetContext
        self.targetDisplayIDs = targetDisplayIDs
        self.diagnostic = diagnostic
        self.shouldExecute = shouldExecute
    }
}

public struct ContextActivationIntent: Equatable, Sendable {
    public let targetContext: ContextDefinition?
    public let targetDisplayIDs: [String]
    public let diagnostic: DiagnosticState?
    public let shouldExecute: Bool

    public init(
        targetContext: ContextDefinition?,
        targetDisplayIDs: [String] = [],
        diagnostic: DiagnosticState?,
        shouldExecute: Bool
    ) {
        self.targetContext = targetContext
        self.targetDisplayIDs = targetDisplayIDs
        self.diagnostic = diagnostic
        self.shouldExecute = shouldExecute
    }
}

public struct ContextPlan: Equatable, Codable, Sendable {
    public private(set) var contexts: [ContextDefinition]
    public private(set) var currentContextID: String
    public private(set) var syncState: ContextSyncState
    public private(set) var isPinned: Bool

    private enum CodingKeys: String, CodingKey {
        case contexts
        case currentContextID
        case syncState
        case isPinned
    }

    public init(
        contexts: [ContextDefinition],
        currentContextID: String,
        syncState: ContextSyncState = .synchronized,
        isPinned: Bool = true
    ) {
        self.contexts = Self.normalizedContexts(contexts)
        self.currentContextID = currentContextID
        self.syncState = syncState
        self.isPinned = isPinned
        ensureValidCurrentContext()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let contexts = try container.decodeIfPresent([ContextDefinition].self, forKey: .contexts) ?? []
        let currentContextID = try container.decodeIfPresent(String.self, forKey: .currentContextID)
            ?? contexts.first?.id
            ?? Self.default.currentContextID
        let syncState = try container.decodeIfPresent(ContextSyncState.self, forKey: .syncState) ?? .synchronized
        let isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? true

        self.init(
            contexts: contexts,
            currentContextID: currentContextID,
            syncState: syncState,
            isPinned: isPinned
        )
    }

    public static let `default` = ContextPlan(
        contexts: (1...3).map { index in
            ContextDefinition(id: "context-\(index)", order: index, name: "Context \(index)")
        },
        currentContextID: "context-1",
        syncState: .synchronized,
        isPinned: true
    )

    public var currentContext: ContextDefinition? {
        contexts.first { $0.id == currentContextID }
    }

    @discardableResult
    public mutating func addEmptyContext() -> ContextDefinition {
        let prefix = "context-"
        let highestGeneratedNumber = contexts.compactMap { context -> Int? in
            guard context.id.hasPrefix(prefix) else {
                return nil
            }
            return Int(context.id.dropFirst(prefix.count))
        }.max() ?? 0
        var number = highestGeneratedNumber + 1
        while contexts.contains(where: { $0.id == "context-\(number)" }) {
            number += 1
        }

        let context = ContextDefinition(
            id: "context-\(number)",
            order: contexts.count + 1,
            name: "Context \(number)"
        )
        contexts.append(context)
        return context
    }

    @discardableResult
    public mutating func deleteContext(
        id: String,
        minimumContextCount: Int
    ) -> Bool {
        guard minimumContextCount >= 1,
              contexts.count > minimumContextCount,
              let removedIndex = contexts.firstIndex(where: { $0.id == id })
        else {
            return false
        }

        let removedCurrentContext = currentContextID == id
        contexts.remove(at: removedIndex)
        contexts = Self.normalizedContexts(contexts)
        if removedCurrentContext {
            let fallbackIndex = max(min(removedIndex - 1, contexts.count - 1), 0)
            currentContextID = contexts[fallbackIndex].id
            syncState = .needsSync
        }
        return true
    }

    public mutating func renameContext(id: String, name: String) {
        guard let index = contexts.firstIndex(where: { $0.id == id }) else {
            return
        }
        let context = contexts[index]
        contexts[index] = ContextDefinition(
            id: context.id,
            order: context.order,
            name: name,
            displayIDs: context.displayIDs,
            displaySpaceIndexes: context.displaySpaceIndexes
        )
    }

    public mutating func replaceContexts(
        _ newContexts: [ContextDefinition],
        currentContextID: String
    ) {
        contexts = Self.normalizedContexts(newContexts)
        self.currentContextID = currentContextID
        syncState = .synchronized
        isPinned = true
        ensureValidCurrentContext()
    }

    public mutating func setPinned(_ isPinned: Bool) {
        self.isPinned = isPinned
    }

    @discardableResult
    public mutating func setCurrentContext(id: String) -> Bool {
        guard contexts.contains(where: { $0.id == id }) else {
            return false
        }
        currentContextID = id
        syncState = .synchronized
        return true
    }

    @discardableResult
    public mutating func moveDisplaySpace(
        displayID: String,
        spaceIndex: Int,
        toContextID targetContextID: String
    ) -> Bool {
        guard spaceIndex >= 0,
              let sourceIndex = contexts.firstIndex(where: { $0.spaceIndex(for: displayID) == spaceIndex }),
              let targetIndex = contexts.firstIndex(where: { $0.id == targetContextID }),
              sourceIndex != targetIndex
        else {
            return false
        }

        let affectsCurrentContext = contexts[sourceIndex].id == currentContextID
            || contexts[targetIndex].id == currentContextID
        var mappings = contexts.map(\.displaySpaceIndexes)
        let targetSpaceIndex = mappings[targetIndex][displayID]

        mappings[sourceIndex].removeValue(forKey: displayID)
        if let targetSpaceIndex {
            mappings[sourceIndex][displayID] = targetSpaceIndex
        }
        mappings[targetIndex][displayID] = spaceIndex

        for index in contexts.indices {
            let context = contexts[index]
            contexts[index] = ContextDefinition(
                id: context.id,
                order: context.order,
                name: context.name,
                displayIDs: Array(mappings[index].keys),
                displaySpaceIndexes: mappings[index]
            )
        }
        if affectsCurrentContext {
            syncState = .needsSync
        }
        return true
    }

    public mutating func markNeedsSync() {
        syncState = .needsSync
    }

    public mutating func pauseContextMatchingForUnsynchronizedMovement() {
        syncState = .needsSync
        isPinned = false
    }

    public func navigation(for command: SwitchCommand) -> ContextPlanNavigation {
        guard syncState == .synchronized else {
            return ContextPlanNavigation(
                command: command,
                targetContext: nil,
                diagnostic: DiagnosticState(
                    severity: .warning,
                    title: "Context needs sync",
                    message: "Set the current Context or capture Contexts before switching.",
                    actionLabel: nil
                )
            )
        }

        let sortedContexts = contexts.sorted { $0.order < $1.order }
        guard !sortedContexts.isEmpty else {
            return blockedNavigation(command: command)
        }

        guard let currentIndex = sortedContexts.firstIndex(where: { $0.id == currentContextID }) else {
            let currentOrder = currentContext?.order ?? 0
            let targetContext: ContextDefinition?
            switch command {
            case .previous:
                targetContext = sortedContexts.last { $0.order < currentOrder }
            case .next:
                targetContext = sortedContexts.first { $0.order > currentOrder }
            }

            guard let targetContext else {
                return blockedNavigation(command: command)
            }
            return ContextPlanNavigation(command: command, targetContext: targetContext, diagnostic: nil)
        }

        switch command {
        case .previous:
            guard currentIndex > 0 else {
                return blockedNavigation(command: command)
            }
            return ContextPlanNavigation(command: command, targetContext: sortedContexts[currentIndex - 1], diagnostic: nil)
        case .next:
            guard currentIndex < sortedContexts.index(before: sortedContexts.endIndex) else {
                return blockedNavigation(command: command)
            }
            return ContextPlanNavigation(command: command, targetContext: sortedContexts[currentIndex + 1], diagnostic: nil)
        }
    }

    public func switchIntent(for command: SwitchCommand) -> ContextSwitchIntent {
        guard isPinned else {
            return ContextSwitchIntent(
                command: command,
                targetContext: nil,
                diagnostic: nil,
                shouldExecute: true
            )
        }

        let navigation = navigation(for: command)
        let targetDisplayIDs = navigation.targetContext?.displayIDs ?? []

        return ContextSwitchIntent(
            command: command,
            targetContext: navigation.targetContext,
            targetDisplayIDs: targetDisplayIDs,
            diagnostic: navigation.diagnostic,
            shouldExecute: navigation.isAllowed
        )
    }

    public func activationIntent(forContextID contextID: String) -> ContextActivationIntent {
        guard let targetContext = contexts.first(where: { $0.id == contextID }) else {
            return ContextActivationIntent(
                targetContext: nil,
                diagnostic: DiagnosticState(
                    severity: .info,
                    title: "No current Context",
                    message: "Choose an existing Context.",
                    actionLabel: nil
                ),
                shouldExecute: false
            )
        }

        return ContextActivationIntent(
            targetContext: targetContext,
            targetDisplayIDs: targetContext.displayIDs,
            diagnostic: nil,
            shouldExecute: true
        )
    }

    public mutating func applySuccessfulSwitch(_ command: SwitchCommand) {
        guard isPinned else {
            syncState = .needsSync
            return
        }

        applySuccessfulNavigation(command)
    }

    public mutating func applySuccessfulNavigation(_ command: SwitchCommand) {
        guard let targetContext = navigation(for: command).targetContext else {
            syncState = .needsSync
            return
        }
        currentContextID = targetContext.id
        syncState = .synchronized
    }

    public mutating func applyFailedNavigation(_ command: SwitchCommand) {
        applyFailedNavigation(command, mayHaveMoved: false)
    }

    public mutating func applyFailedNavigation(
        _ command: SwitchCommand,
        mayHaveMoved: Bool
    ) {
        _ = command
        if mayHaveMoved {
            syncState = .needsSync
        }
    }

    public mutating func applyFailedCaptureRestoration() {
        syncState = .needsSync
    }

    private func blockedNavigation(command: SwitchCommand) -> ContextPlanNavigation {
        let title: String
        let message: String
        switch command {
        case .previous:
            title = "No previous Context"
            message = "The current Context is already first."
        case .next:
            title = "No next Context"
            message = "The current Context is already last."
        }

        return ContextPlanNavigation(
            command: command,
            targetContext: nil,
            diagnostic: DiagnosticState(severity: .info, title: title, message: message, actionLabel: nil)
        )
    }

    private static func normalizedContexts(_ contexts: [ContextDefinition]) -> [ContextDefinition] {
        let sorted = contexts.sorted { $0.order < $1.order }
        guard !sorted.isEmpty else {
            return Self.default.contexts
        }

        let reservedIDs = Set(sorted.map(\.id).filter { !$0.isEmpty })
        var usedIDs = Set<String>()
        var nextContextNumber = 1
        func nextAvailableID() -> String {
            var id = "context-\(nextContextNumber)"
            while reservedIDs.contains(id) || usedIDs.contains(id) {
                nextContextNumber += 1
                id = "context-\(nextContextNumber)"
            }
            usedIDs.insert(id)
            nextContextNumber += 1
            return id
        }

        return sorted.enumerated().map { offset, context in
            let id: String
            if !context.id.isEmpty, !usedIDs.contains(context.id) {
                id = context.id
                usedIDs.insert(id)
            } else {
                id = nextAvailableID()
            }

            return ContextDefinition(
                id: id,
                order: offset + 1,
                name: context.name,
                displayIDs: context.displayIDs,
                displaySpaceIndexes: context.displaySpaceIndexes
            )
        }
    }

    private mutating func ensureValidCurrentContext() {
        if contexts.isEmpty {
            contexts = Self.default.contexts
            currentContextID = Self.default.currentContextID
        }
        contexts = Self.normalizedContexts(contexts)
        if !contexts.contains(where: { $0.id == currentContextID }),
           let firstContext = contexts.first {
            currentContextID = firstContext.id
        }
    }
}
