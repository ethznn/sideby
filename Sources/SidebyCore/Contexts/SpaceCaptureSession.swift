public struct SpaceCaptureSession: Equatable, Sendable {
    public let spaceCount: Int
    public private(set) var currentSpaceOrder: Int
    public private(set) var isStopped: Bool

    public init(spaceCount: Int) {
        self.spaceCount = max(spaceCount, 1)
        self.currentSpaceOrder = 1
        self.isStopped = false
    }

    public var currentStep: Int {
        min(currentSpaceOrder, totalSteps)
    }

    public var totalSteps: Int {
        spaceCount
    }

    public var isComplete: Bool {
        isStopped || currentSpaceOrder >= spaceCount
    }

    public func nextCommand() -> SwitchCommand? {
        guard !isStopped, currentSpaceOrder < spaceCount else {
            return nil
        }

        return .next
    }

    public mutating func advanceAfterSuccessfulSwitch() {
        guard !isStopped, currentSpaceOrder < spaceCount else {
            return
        }

        currentSpaceOrder += 1
    }

    public mutating func stop() {
        isStopped = true
    }
}
