import SidebyCore

public struct MenuBarState: Equatable, Sendable {
    public let mode: AppMode
    public let displaySummary: String
    public let permissionState: PermissionState
    public let diagnostics: [DiagnosticState]

    public init(
        mode: AppMode,
        displaySummary: String,
        permissionState: PermissionState,
        diagnostics: [DiagnosticState]
    ) {
        self.mode = mode
        self.displaySummary = displaySummary
        self.permissionState = permissionState
        self.diagnostics = diagnostics
    }

    public init(coordinatorState: AppCoordinatorState) {
        self.init(
            mode: coordinatorState.settings.mode,
            displaySummary: Self.summary(for: coordinatorState.runtimeState.displayLayout),
            permissionState: coordinatorState.runtimeState.accessibilityPermission,
            diagnostics: coordinatorState.diagnostics
        )
    }

    private static func summary(for layout: DisplayLayout) -> String {
        if layout.displayCount == 1 {
            return "1 display"
        }

        return "\(layout.displayCount) displays"
    }
}
