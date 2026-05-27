public enum InputDeviceKind: String, Codable, Equatable, Sendable {
    case macBookTrackpad
    case magicTrackpad
    case magicMouse
    case mouse
}

public struct InputDeviceProfile: Equatable, Codable, Sendable {
    public let kind: InputDeviceKind
    public let defaultThreshold: Double
    public let ignoresMomentum: Bool
    public let naturalScrollingEnabled: Bool

    public init(
        kind: InputDeviceKind,
        defaultThreshold: Double,
        ignoresMomentum: Bool,
        naturalScrollingEnabled: Bool
    ) {
        self.kind = kind
        self.defaultThreshold = defaultThreshold
        self.ignoresMomentum = ignoresMomentum
        self.naturalScrollingEnabled = naturalScrollingEnabled
    }

    public var gestureSettings: GestureSettings {
        GestureSettings(
            requiredModifiers: AppSettings.defaultGestureModifiers,
            horizontalThreshold: defaultThreshold,
            dominanceRatio: 1.4,
            ignoresMomentum: ignoresMomentum,
            naturalScrollingEnabled: naturalScrollingEnabled
        )
    }

    public static let macBookTrackpad = InputDeviceProfile(
        kind: .macBookTrackpad,
        defaultThreshold: 80,
        ignoresMomentum: true,
        naturalScrollingEnabled: true
    )

    public static let magicTrackpad = InputDeviceProfile(
        kind: .magicTrackpad,
        defaultThreshold: 90,
        ignoresMomentum: true,
        naturalScrollingEnabled: true
    )

    public static let magicMouse = InputDeviceProfile(
        kind: .magicMouse,
        defaultThreshold: 70,
        ignoresMomentum: true,
        naturalScrollingEnabled: true
    )

    public static let mouse = InputDeviceProfile(
        kind: .mouse,
        defaultThreshold: 100,
        ignoresMomentum: false,
        naturalScrollingEnabled: true
    )
}
