public enum InputEventType: Equatable, Sendable {
    case scrollWheel
    case flagsChanged
    case keyDown
    case keyUp
}

public enum ScrollPhase: Equatable, Sendable {
    case began
    case changed
    case ended
    case cancelled
    case none
}

public struct ModifierFlags: OptionSet, Codable, Equatable, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let shift = ModifierFlags(rawValue: 1 << 0)
    public static let control = ModifierFlags(rawValue: 1 << 1)
    public static let option = ModifierFlags(rawValue: 1 << 2)
    public static let command = ModifierFlags(rawValue: 1 << 3)
    public static let function = ModifierFlags(rawValue: 1 << 4)

    public static let primaryShortcutModifiers: ModifierFlags = [.control, .option, .command]
    public static let configurableGestureModifiers: ModifierFlags = [.shift, .control, .option, .command]
}

public struct InputEvent: Equatable, Sendable {
    public let type: InputEventType
    public let deltaX: Double
    public let deltaY: Double
    public let modifierFlags: ModifierFlags
    public let phase: ScrollPhase
    public let timestamp: Double
    public let isMomentum: Bool

    public init(
        type: InputEventType,
        deltaX: Double,
        deltaY: Double,
        modifierFlags: ModifierFlags,
        phase: ScrollPhase,
        timestamp: Double,
        isMomentum: Bool
    ) {
        self.type = type
        self.deltaX = deltaX
        self.deltaY = deltaY
        self.modifierFlags = modifierFlags
        self.phase = phase
        self.timestamp = timestamp
        self.isMomentum = isMomentum
    }

    public func replacingModifierFlags(_ modifierFlags: ModifierFlags) -> InputEvent {
        InputEvent(
            type: type,
            deltaX: deltaX,
            deltaY: deltaY,
            modifierFlags: modifierFlags,
            phase: phase,
            timestamp: timestamp,
            isMomentum: isMomentum
        )
    }
}
