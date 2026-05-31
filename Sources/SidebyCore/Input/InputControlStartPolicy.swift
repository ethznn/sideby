public enum InputControlStartDecision: Equatable, Sendable {
    case startListeners
    case waitForPermissions
}

public enum InputControlStartPolicy: Sendable {
    public static func decision(
        hasAccessibilityPermission: Bool,
        hasSwitchingAccess: Bool
    ) -> InputControlStartDecision {
        guard hasAccessibilityPermission, hasSwitchingAccess else {
            return .waitForPermissions
        }

        return .startListeners
    }
}
