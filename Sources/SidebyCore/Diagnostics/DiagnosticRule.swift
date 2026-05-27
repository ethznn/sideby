public enum DiagnosticRule {
    public static func evaluate(decision: ModeDecision) -> [DiagnosticState] {
        var states: [DiagnosticState] = []

        if let blockReason = decision.blockReason {
            states.append(state(for: blockReason))
        }

        states.append(contentsOf: decision.warnings.map(state(for:)))

        return states
    }

    private static func state(for blockReason: PolicyBlockReason) -> DiagnosticState {
        switch blockReason {
        case .accessibilityPermissionMissing:
            DiagnosticState(
                severity: .blocker,
                title: "Accessibility permission is off",
                message: "Enable permission to detect swipes while a key is held.",
                actionLabel: "Open System Settings"
            )
        case .noAvailableSpace:
            DiagnosticState(
                severity: .blocker,
                title: "Only one Space is available",
                message: "Add another Desktop in Mission Control before switching contexts.",
                actionLabel: "Add Desktop"
            )
        }
    }

    private static func state(for warning: PolicyWarning) -> DiagnosticState {
        switch warning {
        case .singleDisplayMode:
            DiagnosticState(
                severity: .info,
                title: "Single Display Mode",
                message: "External display features will activate when another display is connected.",
                actionLabel: nil
            )
        case .experimentalMode:
            DiagnosticState(
                severity: .warning,
                title: "Advanced mode is experimental",
                message: "Separate display Spaces may not stay perfectly synchronized on every macOS setup.",
                actionLabel: nil
            )
        }
    }
}
