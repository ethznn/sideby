public enum InputMethod: Equatable, Sendable {
    case shortcut
    case swipe
}

public enum PermissionState: Equatable, Sendable {
    case granted
    case denied
    case notDetermined
}

public enum PolicyBlockReason: Equatable, Sendable {
    case accessibilityPermissionMissing
    case noAvailableSpace
}

public enum PolicyWarning: Equatable, Sendable {
    case singleDisplayMode
    case experimentalMode
}

public struct RuntimeState: Equatable, Sendable {
    public var accessibilityPermission: PermissionState
    public var displayLayout: DisplayLayout
    public var availableSpaceCount: Int

    public init(
        accessibilityPermission: PermissionState,
        displayLayout: DisplayLayout,
        availableSpaceCount: Int
    ) {
        self.accessibilityPermission = accessibilityPermission
        self.displayLayout = displayLayout
        self.availableSpaceCount = availableSpaceCount
    }
}

public struct ModeDecision: Equatable, Sendable {
    public let isAllowed: Bool
    public let blockReason: PolicyBlockReason?
    public let warnings: [PolicyWarning]
    public let isExperimental: Bool

    public init(
        isAllowed: Bool,
        blockReason: PolicyBlockReason?,
        warnings: [PolicyWarning],
        isExperimental: Bool
    ) {
        self.isAllowed = isAllowed
        self.blockReason = blockReason
        self.warnings = warnings
        self.isExperimental = isExperimental
    }
}

public struct ModePolicy: Sendable {
    public init() {}

    public func decision(
        for mode: AppMode,
        inputMethod: InputMethod,
        runtimeState: RuntimeState
    ) -> ModeDecision {
        if runtimeState.availableSpaceCount <= 1 {
            return ModeDecision(
                isAllowed: false,
                blockReason: .noAvailableSpace,
                warnings: warnings(for: mode, runtimeState: runtimeState),
                isExperimental: mode == .separateDisplays
            )
        }

        if inputMethod == .swipe && runtimeState.accessibilityPermission != .granted {
            return ModeDecision(
                isAllowed: false,
                blockReason: .accessibilityPermissionMissing,
                warnings: warnings(for: mode, runtimeState: runtimeState),
                isExperimental: mode == .separateDisplays
            )
        }

        return ModeDecision(
            isAllowed: true,
            blockReason: nil,
            warnings: warnings(for: mode, runtimeState: runtimeState),
            isExperimental: mode == .separateDisplays
        )
    }

    private func warnings(for mode: AppMode, runtimeState: RuntimeState) -> [PolicyWarning] {
        var warnings: [PolicyWarning] = []

        if !runtimeState.displayLayout.hasExternalDisplay {
            warnings.append(.singleDisplayMode)
        }

        if mode == .separateDisplays {
            warnings.append(.experimentalMode)
        }

        return warnings
    }
}
