public struct SwipeInputPipeline: Sendable {
    private let settings: GestureSettings
    private let engine: GestureEngine
    private var debounceGate: DebounceGate
    private var accumulator: ScrollDeltaAccumulator?
    private let accumulationWindow: Double

    public init(settings: GestureSettings, lockoutInterval: Double = 0.6, accumulationWindow: Double = 0.35) {
        self.settings = settings
        self.engine = GestureEngine(settings: settings)
        self.debounceGate = DebounceGate(lockoutInterval: lockoutInterval)
        self.accumulationWindow = accumulationWindow
    }

    public mutating func command(for event: InputEvent) -> SwitchCommand? {
        guard event.type == .scrollWheel else {
            accumulator = nil
            return nil
        }

        guard InputModifierMatchPolicy.gestureModifiersMatch(
            eventModifiers: event.modifierFlags,
            requiredModifiers: settings.requiredModifiers
        ) else {
            accumulator = nil
            return nil
        }

        if settings.ignoresMomentum && event.isMomentum {
            accumulator = nil
            return nil
        }

        let accumulatedEvent = accumulatedScrollEvent(for: event)
        guard let command = engine.command(for: accumulatedEvent, debounceGate: &debounceGate) else {
            return nil
        }

        accumulator = nil
        return command
    }

    private mutating func accumulatedScrollEvent(for event: InputEvent) -> InputEvent {
        if var current = accumulator, event.timestamp - current.lastTimestamp <= accumulationWindow {
            current.append(event)
            accumulator = current
        } else {
            accumulator = ScrollDeltaAccumulator(event)
        }

        guard let accumulator else {
            return event
        }

        return InputEvent(
            type: .scrollWheel,
            deltaX: accumulator.deltaX,
            deltaY: accumulator.deltaY,
            modifierFlags: event.modifierFlags,
            phase: event.phase,
            timestamp: event.timestamp,
            isMomentum: event.isMomentum
        )
    }
}

private struct ScrollDeltaAccumulator: Sendable {
    private(set) var deltaX: Double
    private(set) var deltaY: Double
    private(set) var lastTimestamp: Double

    init(_ event: InputEvent) {
        self.deltaX = event.deltaX
        self.deltaY = event.deltaY
        self.lastTimestamp = event.timestamp
    }

    mutating func append(_ event: InputEvent) {
        deltaX += event.deltaX
        deltaY += event.deltaY
        lastTimestamp = event.timestamp
    }
}
