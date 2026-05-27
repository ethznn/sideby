public enum OnboardingStep: Equatable, Sendable {
    case displayCheck
    case chooseGesture
    case permissionRationale
    case tryRight
    case tryLeft
    case completed
}

public enum OnboardingEvent: Equatable, Sendable {
    case displaysDetected
    case gestureChosen
    case permissionPromptAccepted
    case rightSwitchSucceeded
    case leftSwitchSucceeded
    case reset
}

public struct OnboardingState: Equatable, Sendable {
    public let step: OnboardingStep
    public let diagnostics: [DiagnosticState]

    public init(step: OnboardingStep, diagnostics: [DiagnosticState] = []) {
        self.step = step
        self.diagnostics = diagnostics
    }
}

public struct OnboardingStateMachine: Sendable {
    public init() {}

    public func reduce(_ state: OnboardingState, event: OnboardingEvent) -> OnboardingState {
        switch (state.step, event) {
        case (_, .reset):
            OnboardingState(step: .displayCheck)
        case (.displayCheck, .displaysDetected):
            OnboardingState(step: .chooseGesture)
        case (.chooseGesture, .gestureChosen):
            OnboardingState(step: .permissionRationale)
        case (.permissionRationale, .permissionPromptAccepted):
            OnboardingState(step: .tryRight)
        case (.tryRight, .rightSwitchSucceeded):
            OnboardingState(step: .tryLeft)
        case (.tryLeft, .leftSwitchSucceeded):
            OnboardingState(step: .completed)
        default:
            state
        }
    }
}
