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

    // observerWait doubles as the attribution window for the global
    // activeSpaceDidChange notification. Shortening it below the space-switch
    // animation time makes notifications bleed into the next display's press
    // window and corrupts per-display movement attribution — keep it
    // conservative until sensing no longer relies on time-windowed
    // notifications.
    public static let automatic = ContextCaptureConfiguration(
        maxAlignmentAttempts: 12,
        observerWait: 0.90,
        alignmentRetryDelay: 0.12,
        forwardRetryDelay: 0.12
    )
}
