public struct ContextDisplaySlot: Equatable, Codable, Sendable {
    public let displayID: String
    public var label: String

    public init(displayID: String, label: String = "") {
        self.displayID = displayID
        self.label = label
    }
}

public struct ContextDefinition: Equatable, Codable, Identifiable, Sendable {
    public let id: String
    public var order: Int
    public var name: String
    public var displaySlots: [ContextDisplaySlot]

    public init(
        id: String,
        order: Int,
        name: String,
        displaySlots: [ContextDisplaySlot] = []
    ) {
        self.id = id
        self.order = order
        self.name = name
        self.displaySlots = displaySlots
    }

    public func label(for displayID: String) -> String? {
        displaySlots.first { $0.displayID == displayID }?.label
    }
}

public struct ContextPlanNavigation: Equatable, Sendable {
    public let command: SwitchCommand
    public let targetContext: ContextDefinition?
    public let diagnostic: DiagnosticState?

    public var isAllowed: Bool {
        targetContext != nil
    }

    public init(
        command: SwitchCommand,
        targetContext: ContextDefinition?,
        diagnostic: DiagnosticState?
    ) {
        self.command = command
        self.targetContext = targetContext
        self.diagnostic = diagnostic
    }
}

public struct ContextPlan: Equatable, Codable, Sendable {
    public var contexts: [ContextDefinition]
    public var currentContextID: String

    public init(contexts: [ContextDefinition], currentContextID: String) {
        self.contexts = contexts.sorted { $0.order < $1.order }
        self.currentContextID = currentContextID
        ensureValidCurrentContext()
    }

    public static let `default` = ContextPlan(
        contexts: (1...3).map { index in
            ContextDefinition(
                id: "context-\(index)",
                order: index,
                name: "Context \(index)"
            )
        },
        currentContextID: "context-1"
    )

    public var currentContext: ContextDefinition? {
        contexts.first { $0.id == currentContextID }
    }

    public mutating func reconcile(with displayLayout: DisplayLayout) {
        ensureNonEmptyContexts()
        contexts.sort { $0.order < $1.order }

        let connectedDisplayIDs = displayLayout.displays.map(\.id)
        for contextIndex in contexts.indices {
            for displayID in connectedDisplayIDs where contexts[contextIndex].label(for: displayID) == nil {
                contexts[contextIndex].displaySlots.append(ContextDisplaySlot(displayID: displayID))
            }
        }

        ensureValidCurrentContext()
    }

    public func label(contextID: String, displayID: String) -> String? {
        contexts
            .first { $0.id == contextID }?
            .label(for: displayID)
    }

    public mutating func updateLabel(contextID: String, displayID: String, label: String) {
        guard let contextIndex = contexts.firstIndex(where: { $0.id == contextID }) else {
            return
        }

        if let slotIndex = contexts[contextIndex].displaySlots.firstIndex(where: { $0.displayID == displayID }) {
            contexts[contextIndex].displaySlots[slotIndex].label = label
        } else {
            contexts[contextIndex].displaySlots.append(
                ContextDisplaySlot(displayID: displayID, label: label)
            )
        }
    }

    @discardableResult
    public mutating func addContext(displayLayout: DisplayLayout) -> ContextDefinition {
        let nextNumber = nextAvailableContextNumber()
        let context = ContextDefinition(
            id: "context-\(nextNumber)",
            order: nextOrder(),
            name: "Context \(nextNumber)",
            displaySlots: displayLayout.displays.map { display in
                ContextDisplaySlot(displayID: display.id)
            }
        )
        contexts.append(context)
        contexts.sort { $0.order < $1.order }
        ensureValidCurrentContext()
        return context
    }

    @discardableResult
    public mutating func deleteContext(id: String) -> Bool {
        guard contexts.count > 1,
              let removedIndex = contexts.firstIndex(where: { $0.id == id })
        else {
            return false
        }

        let removedContextWasCurrent = currentContextID == id
        contexts.remove(at: removedIndex)
        contexts.sort { $0.order < $1.order }

        if removedContextWasCurrent {
            let fallbackIndex = max(min(removedIndex - 1, contexts.count - 1), 0)
            currentContextID = contexts[fallbackIndex].id
        }

        ensureValidCurrentContext()
        return true
    }

    @discardableResult
    public mutating func setCurrentContext(id: String) -> Bool {
        guard contexts.contains(where: { $0.id == id }) else {
            return false
        }

        currentContextID = id
        return true
    }

    public func navigation(for command: SwitchCommand) -> ContextPlanNavigation {
        let sortedContexts = contexts.sorted { $0.order < $1.order }
        guard let currentIndex = sortedContexts.firstIndex(where: { $0.id == currentContextID }) else {
            return ContextPlanNavigation(
                command: command,
                targetContext: sortedContexts.first,
                diagnostic: nil
            )
        }

        switch command {
        case .previous:
            guard currentIndex > 0 else {
                return blockedNavigation(command: command)
            }
            return ContextPlanNavigation(
                command: command,
                targetContext: sortedContexts[currentIndex - 1],
                diagnostic: nil
            )
        case .next:
            guard currentIndex < sortedContexts.index(before: sortedContexts.endIndex) else {
                return blockedNavigation(command: command)
            }
            return ContextPlanNavigation(
                command: command,
                targetContext: sortedContexts[currentIndex + 1],
                diagnostic: nil
            )
        }
    }

    public mutating func applySuccessfulNavigation(_ command: SwitchCommand) {
        guard let targetContext = navigation(for: command).targetContext else {
            return
        }

        currentContextID = targetContext.id
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
            diagnostic: DiagnosticState(
                severity: .info,
                title: title,
                message: message,
                actionLabel: nil
            )
        )
    }

    private func nextOrder() -> Int {
        (contexts.map(\.order).max() ?? 0) + 1
    }

    private func nextAvailableContextNumber() -> Int {
        let existingIDs = Set(contexts.map(\.id))
        var number = (contexts.map(\.order).max() ?? 0) + 1
        while existingIDs.contains("context-\(number)") {
            number += 1
        }
        return number
    }

    private mutating func ensureNonEmptyContexts() {
        if contexts.isEmpty {
            contexts = Self.default.contexts
            currentContextID = Self.default.currentContextID
        }
    }

    private mutating func ensureValidCurrentContext() {
        ensureNonEmptyContexts()
        if !contexts.contains(where: { $0.id == currentContextID }),
           let firstContext = contexts.sorted(by: { $0.order < $1.order }).first {
            currentContextID = firstContext.id
        }
    }
}
