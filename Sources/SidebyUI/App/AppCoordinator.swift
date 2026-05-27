import SidebyCore

public struct AppCoordinatorState: Equatable, Sendable {
    public let settings: AppSettings
    public let runtimeState: RuntimeState
    public let diagnostics: [DiagnosticState]

    public init(
        settings: AppSettings,
        runtimeState: RuntimeState,
        diagnostics: [DiagnosticState]
    ) {
        self.settings = settings
        self.runtimeState = runtimeState
        self.diagnostics = diagnostics
    }
}

public struct AppCoordinator: Sendable {
    private let modePolicy: ModePolicy

    public init(modePolicy: ModePolicy = ModePolicy()) {
        self.modePolicy = modePolicy
    }

    public func state(settings: AppSettings, runtimeState: RuntimeState) -> AppCoordinatorState {
        let decision = modePolicy.decision(
            for: settings.mode,
            inputMethod: settings.mode == .swipe ? .swipe : .shortcut,
            runtimeState: runtimeState
        )

        return AppCoordinatorState(
            settings: settings,
            runtimeState: runtimeState,
            diagnostics: DiagnosticRule.evaluate(decision: decision)
        )
    }
}
