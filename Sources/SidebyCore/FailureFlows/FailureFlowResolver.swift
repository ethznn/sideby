public enum FailureScenario: Equatable, Sendable {
    case accessibilityPermissionOff
    case noAvailableSpace
    case externalDisplayDisconnected
    case displayConfigurationChanged
    case switchExecutionFailed
}

public struct FailureFlowResolver: Sendable {
    public init() {}

    public func diagnostic(for scenario: FailureScenario) -> DiagnosticState {
        switch scenario {
        case .accessibilityPermissionOff:
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
        case .externalDisplayDisconnected:
            DiagnosticState(
                severity: .info,
                title: "Single Display Mode",
                message: "External display features will activate when another display is connected.",
                actionLabel: nil
            )
        case .displayConfigurationChanged:
            DiagnosticState(
                severity: .warning,
                title: "Display layout changed",
                message: "Review this layout before relying on synchronized context switching.",
                actionLabel: "Review Displays"
            )
        case .switchExecutionFailed:
            DiagnosticState(
                severity: .warning,
                title: "Context did not switch",
                message: "The system did not accept the switch command. Try again from the menu bar controls.",
                actionLabel: nil
            )
        }
    }
}
