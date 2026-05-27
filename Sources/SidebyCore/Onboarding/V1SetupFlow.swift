public struct V1SetupStatus: Equatable, Sendable {
    public let displayCount: Int
    public let selectedTargetCount: Int
    public let accessibilityPermission: PermissionState
    public let isSidebyEnabled: Bool
    public let didCompleteOnboarding: Bool

    public init(
        displayCount: Int,
        selectedTargetCount: Int,
        accessibilityPermission: PermissionState,
        isSidebyEnabled: Bool,
        didCompleteOnboarding: Bool
    ) {
        self.displayCount = displayCount
        self.selectedTargetCount = selectedTargetCount
        self.accessibilityPermission = accessibilityPermission
        self.isSidebyEnabled = isSidebyEnabled
        self.didCompleteOnboarding = didCompleteOnboarding
    }
}

public struct V1SetupViewState: Equatable, Sendable {
    public let title: String
    public let status: String
    public let primaryActionTitle: String
    public let canCompleteSetup: Bool

    public init(
        title: String,
        status: String,
        primaryActionTitle: String,
        canCompleteSetup: Bool
    ) {
        self.title = title
        self.status = status
        self.primaryActionTitle = primaryActionTitle
        self.canCompleteSetup = canCompleteSetup
    }
}

public struct V1SetupFlow: Sendable {
    public init() {}

    public func viewState(for status: V1SetupStatus) -> V1SetupViewState {
        if status.displayCount == 0 {
            return V1SetupViewState(
                title: "No displays detected",
                status: "Connect a display or refresh before setting up Sideby.",
                primaryActionTitle: "Refresh Displays",
                canCompleteSetup: false
            )
        }

        if status.selectedTargetCount == 0 {
            return V1SetupViewState(
                title: "\(displayText(status.displayCount)) detected",
                status: "Select at least one display to move.",
                primaryActionTitle: "Select Move Targets",
                canCompleteSetup: false
            )
        }

        if status.accessibilityPermission != .granted {
            return V1SetupViewState(
                title: "Permission needed",
                status: "Input is used only while Sideby is on. Raw input is not stored.",
                primaryActionTitle: "Enable Accessibility",
                canCompleteSetup: false
            )
        }

        if !status.isSidebyEnabled {
            return V1SetupViewState(
                title: "Ready to turn on",
                status: "Turn on Sideby to enable swipe gestures and test buttons.",
                primaryActionTitle: "Turn On Sideby",
                canCompleteSetup: true
            )
        }

        return V1SetupViewState(
            title: "Sideby is on",
            status: "Use Option + Shift + horizontal scroll. Keyboard shortcuts can be enabled in Input settings.",
            primaryActionTitle: status.didCompleteOnboarding ? "Open Settings" : "Complete Setup",
            canCompleteSetup: true
        )
    }

    private func displayText(_ count: Int) -> String {
        count == 1 ? "1 display" : "\(count) displays"
    }
}
