import SidebyCore

public enum ContextCaptureStatusDisplay {
    public static func statusText(
        phase: ContextCapturePhase,
        maxAlignmentAttempts: Int? = nil,
        completedContextCount: Int,
        currentContextName: String? = nil,
        strings: SBSStrings
    ) -> String {
        switch phase {
        case .aligning(let attempt):
            return strings.aligningToFirstSpace(
                attempt: attempt,
                maxAttempts: maxAlignmentAttempts
            )
        case .capturing(let order):
            return strings.capturingContext(current: order)
        case .completed:
            guard let currentContextName else {
                return strings.capturedContexts(count: completedContextCount)
            }
            return strings.contextCaptureReadySummary(
                count: completedContextCount,
                currentName: currentContextName
            )
        case .failed(let reason):
            return strings.contextCaptureFailed(reason)
        case .stopped:
            return strings.contextCaptureStopped
        }
    }

    public static func statusText(
        session: ContextCaptureSession,
        currentContextName: String? = nil,
        strings: SBSStrings
    ) -> String {
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
            maxAlignmentAttempts: session.maxAlignmentAttempts,
            completedContextCount: completedContextCount,
            currentContextName: currentContextName,
            strings: strings
        )
    }

    public static func progressValue(session: ContextCaptureSession) -> Double? {
        switch session.phase {
        case .aligning(let attempt):
            let attempts = max(session.maxAlignmentAttempts, 1)
            return min(0.16, max(0.04, Double(attempt) / Double(attempts) * 0.16))
        case .capturing:
            return nil
        case .completed:
            return 1
        case .failed, .stopped:
            return 0
        }
    }
}
