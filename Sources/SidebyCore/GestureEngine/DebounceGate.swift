public struct DebounceGate: Sendable {
    public let lockoutInterval: Double
    private var lastAcceptedTimestamp: Double?

    public init(lockoutInterval: Double) {
        self.lockoutInterval = lockoutInterval
        self.lastAcceptedTimestamp = nil
    }

    public mutating func accepts(_ event: InputEvent, settings: GestureSettings) -> Bool {
        if settings.ignoresMomentum && event.isMomentum {
            return false
        }

        if let lastAcceptedTimestamp,
           event.timestamp - lastAcceptedTimestamp < lockoutInterval {
            return false
        }

        lastAcceptedTimestamp = event.timestamp
        return true
    }
}
