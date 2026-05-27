public struct GestureSettings: Equatable, Sendable {
    public let requiredModifiers: ModifierFlags
    public let horizontalThreshold: Double
    public let dominanceRatio: Double
    public let ignoresMomentum: Bool
    public let naturalScrollingEnabled: Bool

    public init(
        requiredModifiers: ModifierFlags,
        horizontalThreshold: Double,
        dominanceRatio: Double,
        ignoresMomentum: Bool,
        naturalScrollingEnabled: Bool
    ) {
        self.requiredModifiers = requiredModifiers
        self.horizontalThreshold = horizontalThreshold
        self.dominanceRatio = dominanceRatio
        self.ignoresMomentum = ignoresMomentum
        self.naturalScrollingEnabled = naturalScrollingEnabled
    }

    public static let `default` = GestureSettings(
        requiredModifiers: AppSettings.defaultGestureModifiers,
        horizontalThreshold: 80,
        dominanceRatio: 1.4,
        ignoresMomentum: true,
        naturalScrollingEnabled: true
    )
}
