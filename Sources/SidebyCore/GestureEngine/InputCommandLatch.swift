public enum InputCommandSource: Equatable, Sendable {
    case swipe
    case keyboard
}

public struct LatchedInputCommand: Equatable, Sendable {
    public let command: SwitchCommand
    public let source: InputCommandSource

    public init(command: SwitchCommand, source: InputCommandSource) {
        self.command = command
        self.source = source
    }
}

public enum InputModifierReleasePolicy {
    public static func didReleaseAllTriggerModifiers(
        currentModifiers: ModifierFlags,
        triggerModifiers: ModifierFlags
    ) -> Bool {
        currentModifiers.intersection(triggerModifiers).isEmpty
    }
}

public enum InputModifierStateCombiner {
    public static func effectiveModifiers(
        eventModifiers: ModifierFlags,
        currentModifiers: ModifierFlags
    ) -> ModifierFlags {
        eventModifiers.union(currentModifiers)
    }
}

public enum InputModifierMatchPolicy {
    public static func gestureModifiersMatch(
        eventModifiers: ModifierFlags,
        requiredModifiers: ModifierFlags
    ) -> Bool {
        eventModifiers.intersection(.configurableGestureModifiers) == requiredModifiers
    }
}

public enum InputCommandLatchState: Equatable, Sendable {
    case idle
    case pending(LatchedInputCommand)
    case switching
    case coolingDown(until: Double)
}

public struct InputCommandLatch: Sendable {
    public static let defaultCooldownInterval = 0.08

    public let cooldownInterval: Double
    public private(set) var state: InputCommandLatchState

    public init(cooldownInterval: Double = Self.defaultCooldownInterval) {
        self.cooldownInterval = cooldownInterval
        self.state = .idle
    }

    public var isBusy: Bool {
        switch state {
        case .idle:
            false
        case .pending, .switching, .coolingDown:
            true
        }
    }

    public mutating func allowsInput(at timestamp: Double) -> Bool {
        expireCooldownIfNeeded(at: timestamp)
        return state == .idle
    }

    @discardableResult
    public mutating func accept(
        _ command: SwitchCommand,
        source: InputCommandSource,
        at timestamp: Double
    ) -> Bool {
        guard allowsInput(at: timestamp) else {
            return false
        }

        state = .pending(LatchedInputCommand(command: command, source: source))
        return true
    }

    public mutating func releasePending(source: InputCommandSource) -> SwitchCommand? {
        guard case let .pending(latchedCommand) = state,
              latchedCommand.source == source
        else {
            return nil
        }

        state = .switching
        return latchedCommand.command
    }

    @discardableResult
    public mutating func beginSwitch(
        _ command: SwitchCommand,
        source: InputCommandSource,
        at timestamp: Double
    ) -> Bool {
        guard allowsInput(at: timestamp) else {
            return false
        }

        state = .switching
        return true
    }

    public mutating func finishSwitch(at timestamp: Double) {
        state = .coolingDown(until: timestamp + cooldownInterval)
    }

    public mutating func reset() {
        state = .idle
    }

    public mutating func expireCooldownIfNeeded(at timestamp: Double) {
        guard case let .coolingDown(until) = state, timestamp >= until else {
            return
        }

        state = .idle
    }
}
