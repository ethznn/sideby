public struct GestureEngine: Sendable {
    private let settings: GestureSettings
    private let classifier: SwipeClassifier

    public init(settings: GestureSettings) {
        self.settings = settings
        self.classifier = SwipeClassifier(settings: settings)
    }

    public func command(for event: InputEvent) -> SwitchCommand? {
        switch classifier.direction(for: event) {
        case .left:
            .previous
        case .right:
            .next
        case nil:
            nil
        }
    }

    public func command(for event: InputEvent, debounceGate: inout DebounceGate) -> SwitchCommand? {
        guard let command = command(for: event) else {
            return nil
        }

        guard debounceGate.accepts(event, settings: settings) else {
            return nil
        }

        return command
    }
}
