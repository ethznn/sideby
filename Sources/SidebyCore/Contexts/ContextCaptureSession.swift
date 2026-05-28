public struct ContextCaptureSession: Equatable, Sendable {
    public let contextIDs: [String]
    public private(set) var currentIndex: Int
    public private(set) var isStopped: Bool

    public init?(plan: ContextPlan) {
        let sortedContexts = plan.contexts.sorted { $0.order < $1.order }
        guard let startIndex = sortedContexts.firstIndex(where: { $0.id == plan.currentContextID }) else {
            return nil
        }

        let captureLimit = min(max(plan.captureLimit, 1), 12)
        self.contextIDs = Array(sortedContexts[startIndex...].map(\.id).prefix(captureLimit))
        self.currentIndex = 0
        self.isStopped = false
    }

    public var currentContextID: String? {
        guard contextIDs.indices.contains(currentIndex) else {
            return nil
        }

        return contextIDs[currentIndex]
    }

    public var currentStep: Int {
        min(currentIndex + 1, totalSteps)
    }

    public var totalSteps: Int {
        contextIDs.count
    }

    public var isComplete: Bool {
        isStopped || currentIndex >= contextIDs.count - 1
    }

    public func nextCommand() -> SwitchCommand? {
        guard !isStopped, currentIndex < contextIDs.count - 1 else {
            return nil
        }

        return .next
    }

    public mutating func advanceAfterSuccessfulSwitch() {
        guard !isStopped, currentIndex < contextIDs.count - 1 else {
            return
        }

        currentIndex += 1
    }

    public mutating func stop() {
        isStopped = true
    }
}
