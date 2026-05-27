import SidebyCore

public struct OnboardingViewState: Equatable, Sendable {
    public let title: String
    public let instruction: String
    public let step: OnboardingStep

    public init(title: String, instruction: String, step: OnboardingStep) {
        self.title = title
        self.instruction = instruction
        self.step = step
    }
}

public struct OnboardingViewModel: Sendable {
    public init() {}

    public func viewState(for state: OnboardingState, displayLayout: DisplayLayout) -> OnboardingViewState {
        switch state.step {
        case .displayCheck:
            return OnboardingViewState(
                title: "\(displayLayout.displayCount) display\(displayLayout.displayCount == 1 ? "" : "s") connected",
                instruction: "Move these displays as one work set.",
                step: state.step
            )
        case .chooseGesture:
            return OnboardingViewState(
                title: "Choose Gesture",
                instruction: "Option + Shift + horizontal swipe is recommended.",
                step: state.step
            )
        case .permissionRationale:
            return OnboardingViewState(
                title: "Permission",
                instruction: "Permission is used to detect swipes while a key is held. Input is not stored.",
                step: state.step
            )
        case .tryRight:
            return OnboardingViewState(
                title: "Try Right",
                instruction: "Hold Option + Shift and swipe right.",
                step: state.step
            )
        case .tryLeft:
            return OnboardingViewState(
                title: "Try Left",
                instruction: "Hold Option + Shift and swipe left.",
                step: state.step
            )
        case .completed:
            return OnboardingViewState(
                title: "Ready",
                instruction: "Sideby now runs from the menu bar.",
                step: state.step
            )
        }
    }
}
