public enum PermissionRequestAction: Equatable, Sendable {
    case openAccessibilitySettings
    case openAutomationSettings
}

public struct PermissionRequestFeedback: Equatable, Sendable {
    public let kind: Kind
    public let action: PermissionRequestAction?

    public enum Kind: Equatable, Sendable {
        case postEventsRequesting
        case switchingAccessRequesting
        case postEventsDenied
        case automationDenied
        case automationNotRegistered
    }

    public init(kind: Kind, action: PermissionRequestAction?) {
        self.kind = kind
        self.action = action
    }

    public static let postEventsDenied = PermissionRequestFeedback(
        kind: .postEventsDenied,
        action: .openAccessibilitySettings
    )

    public static let postEventsRequesting = PermissionRequestFeedback(
        kind: .postEventsRequesting,
        action: nil
    )

    public static let switchingAccessRequesting = PermissionRequestFeedback(
        kind: .switchingAccessRequesting,
        action: nil
    )

    public static let automationDenied = PermissionRequestFeedback(
        kind: .automationDenied,
        action: .openAutomationSettings
    )

    public static let automationNotRegistered = PermissionRequestFeedback(
        kind: .automationNotRegistered,
        action: nil
    )
}

public struct PermissionRequestFeedbackResolver: Sendable {
    public init() {}

    public func postEventFeedback(isGranted: Bool) -> PermissionRequestFeedback? {
        isGranted ? nil : .postEventsDenied
    }

    public func switchingAccessFeedback(
        postEventsGranted: Bool,
        automationGranted: Bool
    ) -> PermissionRequestFeedback? {
        if !postEventsGranted {
            return .postEventsDenied
        }
        if !automationGranted {
            return .automationDenied
        }
        return nil
    }

    public func switchingAccessFeedback(
        postEventsGranted: Bool,
        automationStatusCode: Int32
    ) -> PermissionRequestFeedback? {
        if !postEventsGranted {
            return .postEventsDenied
        }
        if automationStatusCode == 0 {
            return nil
        }
        if automationStatusCode == -600 {
            return .automationNotRegistered
        }
        return .automationDenied
    }
}
