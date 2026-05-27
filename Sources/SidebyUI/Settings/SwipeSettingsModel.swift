import SidebyCore

public struct SwipeSettingsModel: Equatable, Sendable {
    public var requiredModifiers: ModifierFlags
    public var threshold: Double
    public var naturalScrollingEnabled: Bool
    public var ignoresMomentum: Bool

    public init(
        requiredModifiers: ModifierFlags,
        threshold: Double,
        naturalScrollingEnabled: Bool,
        ignoresMomentum: Bool
    ) {
        self.requiredModifiers = requiredModifiers
        self.threshold = threshold
        self.naturalScrollingEnabled = naturalScrollingEnabled
        self.ignoresMomentum = ignoresMomentum
    }

    public init(settings: GestureSettings) {
        self.init(
            requiredModifiers: settings.requiredModifiers,
            threshold: settings.horizontalThreshold,
            naturalScrollingEnabled: settings.naturalScrollingEnabled,
            ignoresMomentum: settings.ignoresMomentum
        )
    }

    public var gestureSettings: GestureSettings {
        GestureSettings(
            requiredModifiers: requiredModifiers,
            horizontalThreshold: threshold,
            dominanceRatio: 1.4,
            ignoresMomentum: ignoresMomentum,
            naturalScrollingEnabled: naturalScrollingEnabled
        )
    }
}
