import SidebyCore

public struct HUDPresentationState: Equatable, Sendable {
    public let text: String
    public let isCompact: Bool
    public let duration: Double

    public init(text: String, isCompact: Bool = false, duration: Double = 0.8) {
        self.text = text
        self.isCompact = isCompact
        self.duration = duration
    }
}

public struct HUDPresenter: Sendable {
    public init() {}

    public func state(for command: SwitchCommand, contextName: String? = nil) -> HUDPresentationState {
        let arrow = command == .next ? "->" : "<-"
        let label = contextName ?? (command == .next ? "Next Context" : "Previous Context")
        return HUDPresentationState(text: "\(arrow) \(label)")
    }

    public func state(for diagnostic: DiagnosticState, compact: Bool = false) -> HUDPresentationState {
        HUDPresentationState(text: diagnostic.title, isCompact: compact)
    }

    public func stateForContextNeedsSync(
        strings: SBSStrings = SBSStrings(language: .english)
    ) -> HUDPresentationState {
        HUDPresentationState(text: strings.contextNeedsSync, isCompact: true)
    }
}
