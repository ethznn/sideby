import SidebyCore

public enum ContextCaptureStatusDisplay {
    public static func statusText(
        phase: ContextCapturePhase,
        captureLimit: Int,
        completedContextCount: Int,
        strings: SBSStrings
    ) -> String {
        switch phase {
        case .aligning:
            return strings.aligningToFirstSpace
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
            completedContextCount: completedContextCount,
            strings: strings
        )
    }
}
