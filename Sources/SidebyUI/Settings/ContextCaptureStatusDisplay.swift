public enum ContextCaptureStatusDisplay {
    public static func statusText(
        contextName: String,
        currentStep: Int,
        totalSteps: Int,
        strings: SBSStrings
    ) -> String {
        strings.capturingContext(
            current: currentStep,
            total: totalSteps,
            name: contextName
        )
    }
}
