public enum DiagnosticSeverity: Equatable, Sendable {
    case info
    case warning
    case blocker
}

public struct DiagnosticState: Equatable, Sendable {
    public let severity: DiagnosticSeverity
    public let title: String
    public let message: String
    public let actionLabel: String?

    public init(
        severity: DiagnosticSeverity,
        title: String,
        message: String,
        actionLabel: String?
    ) {
        self.severity = severity
        self.title = title
        self.message = message
        self.actionLabel = actionLabel
    }
}
