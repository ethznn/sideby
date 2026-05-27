public enum InputExecutionStrategy: String, CaseIterable, Codable, Identifiable, Sendable {
    case modifierRelease

    public var id: Self { self }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = InputExecutionStrategy(rawValue: rawValue) ?? .modifierRelease
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum AppLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    case english = "en"
    case korean = "ko"

    public var id: Self { self }
}

public struct AppSettings: Equatable, Codable, Sendable {
    public static let currentVersion = 12
    public static let defaultGestureModifiers: ModifierFlags = [.option, .shift]
    public static let defaultShortcutModifiers: ModifierFlags = [.option, .shift]

    public var version: Int
    public var mode: AppMode
    public var language: AppLanguage
    public var requiredModifiers: ModifierFlags
    public var keyboardShortcutsEnabled: Bool
    public var shortcutNext: KeyboardShortcut
    public var shortcutPrevious: KeyboardShortcut
    public var inputExecutionStrategy: InputExecutionStrategy
    public var horizontalThreshold: Double
    public var launchAtLogin: Bool
    public var contextPlan: ContextPlan
    public var displaySpacePlan: DisplaySpacePlan

    public init(
        version: Int,
        mode: AppMode,
        language: AppLanguage,
        requiredModifiers: ModifierFlags,
        keyboardShortcutsEnabled: Bool,
        shortcutNext: KeyboardShortcut,
        shortcutPrevious: KeyboardShortcut,
        inputExecutionStrategy: InputExecutionStrategy,
        horizontalThreshold: Double,
        launchAtLogin: Bool,
        contextPlan: ContextPlan,
        displaySpacePlan: DisplaySpacePlan
    ) {
        self.version = version
        self.mode = mode
        self.language = language
        self.requiredModifiers = requiredModifiers
        self.keyboardShortcutsEnabled = keyboardShortcutsEnabled
        self.shortcutNext = shortcutNext
        self.shortcutPrevious = shortcutPrevious
        self.inputExecutionStrategy = inputExecutionStrategy
        self.horizontalThreshold = horizontalThreshold
        self.launchAtLogin = launchAtLogin
        self.contextPlan = contextPlan
        self.displaySpacePlan = displaySpacePlan
    }

    public static let `default` = AppSettings(
        version: currentVersion,
        mode: .together,
        language: .english,
        requiredModifiers: defaultGestureModifiers,
        keyboardShortcutsEnabled: false,
        shortcutNext: KeyboardShortcut(keyCode: 124, modifiers: defaultShortcutModifiers),
        shortcutPrevious: KeyboardShortcut(keyCode: 123, modifiers: defaultShortcutModifiers),
        inputExecutionStrategy: .modifierRelease,
        horizontalThreshold: 80,
        launchAtLogin: false,
        contextPlan: .default,
        displaySpacePlan: .default
    )

    private enum CodingKeys: String, CodingKey {
        case version
        case mode
        case language
        case requiredModifiers
        case keyboardShortcutsEnabled
        case shortcutNext
        case shortcutPrevious
        case inputExecutionStrategy
        case horizontalThreshold
        case launchAtLogin
        case contextPlan
        case displaySpacePlan
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decode(Int.self, forKey: .version)
        self.mode = try container.decode(AppMode.self, forKey: .mode)
        self.language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .english
        self.requiredModifiers = try container.decode(ModifierFlags.self, forKey: .requiredModifiers)
        self.keyboardShortcutsEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .keyboardShortcutsEnabled
        ) ?? false
        self.shortcutNext = try container.decode(KeyboardShortcut.self, forKey: .shortcutNext)
        self.shortcutPrevious = try container.decode(KeyboardShortcut.self, forKey: .shortcutPrevious)
        self.inputExecutionStrategy = try container.decodeIfPresent(
            InputExecutionStrategy.self,
            forKey: .inputExecutionStrategy
        ) ?? .modifierRelease
        self.horizontalThreshold = try container.decode(Double.self, forKey: .horizontalThreshold)
        self.launchAtLogin = try container.decode(Bool.self, forKey: .launchAtLogin)
        self.contextPlan = try container.decodeIfPresent(ContextPlan.self, forKey: .contextPlan) ?? .default
        self.displaySpacePlan = try container.decodeIfPresent(DisplaySpacePlan.self, forKey: .displaySpacePlan) ?? .default
    }
}

public protocol SettingsStoring: Sendable {
    func load() -> AppSettings
    func save(_ settings: AppSettings)
}
