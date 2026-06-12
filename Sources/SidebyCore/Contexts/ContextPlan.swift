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

    private enum CodingKeys: String, CodingKey {
        case id
        case order
        case name
        case displayIDs
    }

    public init(
        id: String,
        order: Int,
        name: String,
        displayIDs: [String] = []
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = id
        self.order = max(order, 1)
        self.name = trimmedName.isEmpty
            ? "Context \(max(order, 1))"
            : trimmedName
        self.displayIDs = Self.normalizedDisplayIDs(displayIDs)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            order: try container.decodeIfPresent(Int.self, forKey: .order) ?? 1,
            name: try container.decodeIfPresent(String.self, forKey: .name) ?? "",
            displayIDs: try container.decodeIfPresent([String].self, forKey: .displayIDs) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(order, forKey: .order)
        try container.encode(name, forKey: .name)
        try container.encode(displayIDs, forKey: .displayIDs)
    }

    private static func normalizedDisplayIDs(_ displayIDs: [String]) -> [String] {
        var seen = Set<String>()
        return displayIDs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
            .filter { seen.insert($0).inserted }
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

public struct ContextPlan: Equatable, Codable, Sendable {
    public private(set) var contexts: [ContextDefinition]
    public private(set) var currentContextID: String
    public private(set) var syncState: ContextSyncState
    public private(set) var captureLimit: Int
    public private(set) var isPinned: Bool

    private enum CodingKeys: String, CodingKey {
        case contexts
        case currentContextID
        case syncState
        case captureLimit
        case isPinned
    }

    public init(
        contexts: [ContextDefinition],
        currentContextID: String,
        syncState: ContextSyncState = .synchronized,
        captureLimit: Int? = nil,
        isPinned: Bool = true
    ) {
        self.contexts = Self.normalizedContexts(contexts)
        self.currentContextID = currentContextID
        self.syncState = syncState
        self.captureLimit = max(captureLimit ?? self.contexts.count, 1)
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
        let captureLimit = try container.decodeIfPresent(Int.self, forKey: .captureLimit)
        let isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? true

        self.init(
            contexts: contexts,
            currentContextID: currentContextID,
            syncState: syncState,
            captureLimit: captureLimit,
            isPinned: isPinned
        )
    }

    public static let `default` = ContextPlan(
        contexts: (1...3).map { index in
            ContextDefinition(id: "context-\(index)", order: index, name: "Context \(index)")
        },
        currentContextID: "context-1",
        syncState: .synchronized,
        captureLimit: 3,
        isPinned: true
    )

    public var currentContext: ContextDefinition? {
        contexts.first { $0.id == currentContextID }
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
            displayIDs: context.displayIDs
        )
    }

    public mutating func replaceContexts(
        _ newContexts: [ContextDefinition],
        currentContextID: String,
        captureLimit: Int
    ) {
        contexts = Self.normalizedContexts(newContexts)
        self.currentContextID = currentContextID
        self.captureLimit = max(captureLimit, 1)
        syncState = .synchronized
        isPinned = true
        ensureValidCurrentContext()
    }

    public mutating func setCaptureLimit(_ limit: Int) {
        captureLimit = min(max(limit, 1), 12)
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
        let targetDisplayIDs: [String]
        switch command {
        case .previous:
            targetDisplayIDs = currentContext?.displayIDs ?? navigation.targetContext?.displayIDs ?? []
        case .next:
            targetDisplayIDs = currentContext?.displayIDs ?? navigation.targetContext?.displayIDs ?? []
        }

        return ContextSwitchIntent(
            command: command,
            targetContext: navigation.targetContext,
            targetDisplayIDs: targetDisplayIDs,
            diagnostic: navigation.diagnostic,
            shouldExecute: navigation.isAllowed
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
        _ = command
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
                displayIDs: context.displayIDs
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
        captureLimit = min(max(captureLimit, 1), 12)
    }
}
