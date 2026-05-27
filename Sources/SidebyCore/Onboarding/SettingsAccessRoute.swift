public enum SettingsAccessAction: Equatable {
    case openSettings
    case customizeShortcuts
    case replayOnboarding
}

public enum SettingsAccessDestination: Equatable {
    case overview
    case input
}

public enum SettingsAccessRoute: Equatable {
    case mainSettings(SettingsAccessDestination)
    case onboarding

    public static func route(
        for action: SettingsAccessAction,
        didCompleteOnboarding: Bool
    ) -> SettingsAccessRoute {
        switch action {
        case .openSettings:
            return .mainSettings(.overview)
        case .customizeShortcuts:
            return .mainSettings(.input)
        case .replayOnboarding:
            return .onboarding
        }
    }
}
