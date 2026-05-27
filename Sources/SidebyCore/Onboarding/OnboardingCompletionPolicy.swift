public struct OnboardingCompletionDefaults: Equatable, Sendable {
    public let selectedDisplayIDs: Set<String>
    public let isSidebyEnabled: Bool

    public init(selectedDisplayIDs: Set<String>, isSidebyEnabled: Bool) {
        self.selectedDisplayIDs = selectedDisplayIDs
        self.isSidebyEnabled = isSidebyEnabled
    }
}

public struct OnboardingCompletionPolicy: Sendable {
    public init() {}

    public func completionDefaults(for displayLayout: DisplayLayout) -> OnboardingCompletionDefaults {
        OnboardingCompletionDefaults(
            selectedDisplayIDs: Set(displayLayout.displays.map(\.id)),
            isSidebyEnabled: true
        )
    }
}
