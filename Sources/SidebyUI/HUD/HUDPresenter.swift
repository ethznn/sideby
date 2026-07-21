import SidebyCore

public struct HUDPresentationState: Equatable, Sendable {
    public let text: String
    public let isCompact: Bool
    public let duration: Double
    public let fadeOutDuration: Double
    public let visualScale: Double
    public let backgroundOpacity: Double

    public init(
        text: String,
        isCompact: Bool = false,
        duration: Double = 0.8,
        fadeOutDuration: Double = 0.24,
        visualScale: Double = 1.0,
        backgroundOpacity: Double = 0.0
    ) {
        self.text = text
        self.isCompact = isCompact
        self.duration = duration
        self.fadeOutDuration = fadeOutDuration
        self.visualScale = visualScale
        self.backgroundOpacity = backgroundOpacity
    }
}

public struct HUDPresenter: Sendable {
    public init() {}

    public func state(for command: SwitchCommand, contextName: String? = nil) -> HUDPresentationState {
        let arrow = command == .next ? "->" : "<-"
        let label = contextName ?? (command == .next ? "Next Context" : "Previous Context")
        return HUDPresentationState(text: "\(arrow) \(label)")
    }

    public func stateForContextSwitch(contextName: String) -> HUDPresentationState {
        HUDPresentationState(
            text: contextName,
            duration: 1.0,
            fadeOutDuration: 0.28,
            visualScale: 4.0,
            backgroundOpacity: 0.66
        )
    }

    public func state(for diagnostic: DiagnosticState, compact: Bool = false) -> HUDPresentationState {
        HUDPresentationState(text: diagnostic.title, isCompact: compact)
    }

    public func stateForContextNeedsSync(
        strings: SBSStrings = SBSStrings(language: .english)
    ) -> HUDPresentationState {
        HUDPresentationState(text: strings.contextNeedsSync, isCompact: true)
    }

    public func stateForSidebyToggleOff(
        strings: SBSStrings = SBSStrings(language: .english)
    ) -> HUDPresentationState {
        HUDPresentationState(text: strings.sidebyToggleOffHUD, isCompact: true)
    }

    public func stateForMissingContext(
        position: Int,
        strings: SBSStrings = SBSStrings(language: .english)
    ) -> HUDPresentationState {
        HUDPresentationState(text: strings.missingContextHUD(position: position), isCompact: true)
    }
}
