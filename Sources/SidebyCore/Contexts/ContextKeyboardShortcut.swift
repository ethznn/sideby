public enum ContextKeyboardCommand: Equatable, Sendable {
    case activate(position: Int)
    case move(SwitchCommand)
}

public struct ContextKeyboardShortcutBinding: Equatable, Sendable {
    public let shortcut: KeyboardShortcut
    public let command: ContextKeyboardCommand

    public init(shortcut: KeyboardShortcut, command: ContextKeyboardCommand) {
        self.shortcut = shortcut
        self.command = command
    }
}

public enum ContextKeyboardShortcutCatalog: Sendable {
    public static let triggerModifiers: ModifierFlags = [.option, .shift]

    public static let bindings: [ContextKeyboardShortcutBinding] = [
        number(position: 1, keyCode: 18),
        number(position: 2, keyCode: 19),
        number(position: 3, keyCode: 20),
        number(position: 4, keyCode: 21),
        number(position: 5, keyCode: 23),
        number(position: 6, keyCode: 22),
        number(position: 7, keyCode: 26),
        number(position: 8, keyCode: 28),
        number(position: 9, keyCode: 25),
        number(position: 10, keyCode: 29),
        binding(keyCode: 43, command: .move(.previous)),
        binding(keyCode: 47, command: .move(.next))
    ]

    public static func binding(
        for command: ContextKeyboardCommand
    ) -> ContextKeyboardShortcutBinding? {
        bindings.first { $0.command == command }
    }

    private static func number(
        position: Int,
        keyCode: UInt16
    ) -> ContextKeyboardShortcutBinding {
        binding(keyCode: keyCode, command: .activate(position: position))
    }

    private static func binding(
        keyCode: UInt16,
        command: ContextKeyboardCommand
    ) -> ContextKeyboardShortcutBinding {
        ContextKeyboardShortcutBinding(
            shortcut: KeyboardShortcut(keyCode: keyCode, modifiers: [.option, .shift]),
            command: command
        )
    }
}

public enum ContextKeyboardAction: Equatable, Sendable {
    case ignore
    case showSidebyOff
    case showMissingContext(position: Int)
    case waitForModifierRelease(ContextKeyboardCommand)
    case activate(contextID: String)
    case move(SwitchCommand)
}

public struct ContextKeyboardExecutionGate: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case idle
        case pending(ContextKeyboardCommand)
        case executing
        case settling(until: Double)
    }

    public private(set) var state: State
    public let settlingDuration: Double

    public init(settlingDuration: Double = 0.75) {
        self.state = .idle
        self.settlingDuration = settlingDuration
    }

    public mutating func reserve(
        _ command: ContextKeyboardCommand,
        at timestamp: Double
    ) -> Bool {
        expireSettling(at: timestamp)

        guard case .idle = state else {
            return false
        }

        state = .pending(command)
        return true
    }

    public mutating func beginExecution(for command: ContextKeyboardCommand) -> Bool {
        guard case .pending(command) = state else {
            return false
        }

        state = .executing
        return true
    }

    public mutating func finishExecution(at timestamp: Double) {
        guard case .executing = state else {
            return
        }

        state = .settling(until: timestamp + settlingDuration)
    }

    public mutating func reset() {
        state = .idle
    }

    private mutating func expireSettling(at timestamp: Double) {
        guard case let .settling(until) = state, timestamp >= until else {
            return
        }

        state = .idle
    }
}

public enum ContextKeyboardShortcutPolicy: Sendable {
    public static func action(
        command: ContextKeyboardCommand,
        contextPlan: ContextPlan,
        isSidebyEnabled: Bool,
        isSwitching: Bool,
        isCapturing: Bool
    ) -> ContextKeyboardAction {
        guard !isSwitching, !isCapturing else {
            return .ignore
        }
        guard isSidebyEnabled else {
            return .showSidebyOff
        }

        switch command {
        case .move(let switchCommand):
            return .move(switchCommand)
        case .activate(let position):
            guard (1...10).contains(position) else {
                return .ignore
            }
            let contexts = contextPlan.contexts.sorted { $0.order < $1.order }
            let index = position - 1
            guard contexts.indices.contains(index) else {
                return .showMissingContext(position: position)
            }
            return .activate(contextID: contexts[index].id)
        }
    }
}
