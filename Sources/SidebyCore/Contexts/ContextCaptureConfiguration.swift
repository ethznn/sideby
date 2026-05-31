public struct ContextCaptureConfiguration: Equatable, Sendable {
    public let maxAlignmentAttempts: Int
    public let observerWait: Double
    public let alignmentRetryDelay: Double
    public let forwardRetryDelay: Double

    public init(
        maxAlignmentAttempts: Int,
        observerWait: Double,
        alignmentRetryDelay: Double,
        forwardRetryDelay: Double
    ) {
        self.maxAlignmentAttempts = min(max(maxAlignmentAttempts, 1), 24)
        self.observerWait = max(observerWait, 0)
        self.alignmentRetryDelay = max(alignmentRetryDelay, 0)
        self.forwardRetryDelay = max(forwardRetryDelay, 0)
    }

    public static let automatic = ContextCaptureConfiguration(
        maxAlignmentAttempts: 12,
        observerWait: 0.90,
        alignmentRetryDelay: 0.12,
        forwardRetryDelay: 0.12
    )
}
