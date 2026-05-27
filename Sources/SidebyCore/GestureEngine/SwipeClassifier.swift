public struct SwipeClassifier: Sendable {
    private let settings: GestureSettings

    public init(settings: GestureSettings) {
        self.settings = settings
    }

    public func direction(for event: InputEvent) -> SwipeDirection? {
        guard event.type == .scrollWheel else {
            return nil
        }

        guard InputModifierMatchPolicy.gestureModifiersMatch(
            eventModifiers: event.modifierFlags,
            requiredModifiers: settings.requiredModifiers
        ) else {
            return nil
        }

        let effectiveDeltaX = Self.effectiveHorizontalDelta(for: event, settings: settings)
        let crossAxisDelta = effectiveDeltaX == event.deltaX ? event.deltaY : event.deltaX
        let horizontalMagnitude = abs(effectiveDeltaX)
        let verticalMagnitude = abs(crossAxisDelta)

        guard horizontalMagnitude >= settings.horizontalThreshold else {
            return nil
        }

        guard horizontalMagnitude >= verticalMagnitude * settings.dominanceRatio else {
            return nil
        }

        let rawDirection: SwipeDirection = effectiveDeltaX >= 0 ? .right : .left
        if settings.naturalScrollingEnabled {
            return rawDirection == .right ? .left : .right
        }

        return rawDirection
    }

    private static func effectiveHorizontalDelta(
        for event: InputEvent,
        settings: GestureSettings
    ) -> Double {
        let horizontalMagnitude = abs(event.deltaX)
        let verticalMagnitude = abs(event.deltaY)
        guard settings.requiredModifiers.contains(.shift),
              event.modifierFlags.contains(.shift),
              verticalMagnitude > horizontalMagnitude
        else {
            return event.deltaX
        }

        return event.deltaY
    }
}
