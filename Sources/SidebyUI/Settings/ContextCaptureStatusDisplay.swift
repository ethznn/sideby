import SidebyCore

public enum ContextCaptureStatusDisplay {
    public static func statusText(
        phase: ContextCapturePhase,
        captureLimit: Int,
        maxAlignmentAttempts: Int? = nil,
        completedContextCount: Int,
        strings: SBSStrings
    ) -> String {
        switch phase {
        case .aligning(let attempt):
            return strings.aligningToFirstSpace(
                attempt: attempt,
                maxAttempts: maxAlignmentAttempts
            )
        case .capturing(let order):
            return strings.capturingContextUpTo(current: order, limit: captureLimit)
        case .completed:
            return strings.capturedContexts(count: completedContextCount)
        case .failed(let reason):
            return strings.contextCaptureFailed(reason)
        case .stopped:
            return strings.contextCaptureStopped
        }
    }

    public static func statusText(session: ContextCaptureSession, strings: SBSStrings) -> String {
        let completedContextCount: Int
        if case .completed = session.phase {
            guard let completedContexts = session.completedContextDefinitions else {
                return strings.contextCaptureFailed("Invalid completed Context capture")
            }
            completedContextCount = completedContexts.count
        } else {
            completedContextCount = 0
        }

        return statusText(
            phase: session.phase,
            captureLimit: session.captureLimit,
            maxAlignmentAttempts: session.maxAlignmentAttempts,
            completedContextCount: completedContextCount,
            strings: strings
        )
    }

    public static func progressValue(session: ContextCaptureSession) -> Double {
        switch session.phase {
        case .aligning(let attempt):
            let attempts = max(session.maxAlignmentAttempts, 1)
            return min(0.16, max(0.04, Double(attempt) / Double(attempts) * 0.16))
        case .capturing(let order):
            let captureLimit = max(session.captureLimit, 1)
            let capturedCount = max(session.draftContexts.count, max(order - 1, 0))
            return min(0.95, max(0.16, Double(capturedCount) / Double(captureLimit)))
        case .completed:
            return 1
        case .failed, .stopped:
            return 0
        }
    }
}
