import SidebyCore

public struct ContextSwitchHUDPresentation: Equatable, Sendable {
    public let state: HUDPresentationState
    public let displayIDs: Set<String>

    public init(state: HUDPresentationState, displayIDs: Set<String>) {
        self.state = state
        self.displayIDs = displayIDs
    }
}

public struct ContextSwitchHUDPolicy: Sendable {
    private let presenter: HUDPresenter

    public init(presenter: HUDPresenter = HUDPresenter()) {
        self.presenter = presenter
    }

    public func presentation(
        for intent: ContextSwitchIntent,
        didExecute: Bool,
        executedDisplayIDs: Set<String>
    ) -> ContextSwitchHUDPresentation? {
        guard didExecute, let targetContext = intent.targetContext else {
            return nil
        }

        let displayIDs = executedDisplayIDs.isEmpty
            ? Set(intent.targetDisplayIDs)
            : executedDisplayIDs

        return ContextSwitchHUDPresentation(
            state: presenter.stateForContextSwitch(contextName: targetContext.name),
            displayIDs: displayIDs
        )
    }
}
