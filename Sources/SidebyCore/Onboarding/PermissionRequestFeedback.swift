public enum PermissionRequestAction: Equatable, Sendable {
    case openAccessibilitySettings
}

public struct PermissionRequestFeedback: Equatable, Sendable {
    public let kind: Kind
    public let action: PermissionRequestAction?

    public enum Kind: Equatable, Sendable {
        case postEventsRequesting
        case switchingAccessRequesting
        case postEventsDenied
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

}

public struct PermissionRequestFeedbackResolver: Sendable {
    public init() {}

    public func postEventFeedback(isGranted: Bool) -> PermissionRequestFeedback? {
        isGranted ? nil : .postEventsDenied
    }

    public func switchingAccessFeedback(
        postEventsGranted: Bool
    ) -> PermissionRequestFeedback? {
        postEventsGranted ? nil : .postEventsDenied
    }
}
