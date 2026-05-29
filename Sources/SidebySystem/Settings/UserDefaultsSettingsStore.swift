import Foundation
import SidebyCore

public final class UserDefaultsSettingsStore: SettingsStoring, @unchecked Sendable {
    public static let sharedSuiteName = "dev.sideby.Sideby.shared"
    public static let settingsDidChangeNotification = Notification.Name("dev.sideby.Sideby.settingsDidChange")

    private let userDefaults: UserDefaults
    private let fallbackUserDefaults: UserDefaults?
    private let key: String

    public init(
        userDefaults: UserDefaults? = nil,
        key: String = "sideby.settings",
        fallbackUserDefaults: UserDefaults? = nil
    ) {
        self.userDefaults = userDefaults ?? Self.sharedUserDefaults()
        self.fallbackUserDefaults = fallbackUserDefaults ?? (userDefaults == nil ? .standard : nil)
        self.key = key
    }

    public func load() -> AppSettings {
        if let settings = load(from: userDefaults) {
            return migrateIfNeeded(settings)
        }

        if let fallbackUserDefaults,
           fallbackUserDefaults !== userDefaults,
           let settings = load(from: fallbackUserDefaults) {
            let migratedSettings = migrate(settings)
            save(migratedSettings)
            return migratedSettings
        }

        return .default
    }

    public func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }

        userDefaults.set(data, forKey: key)
        DistributedNotificationCenter.default().postNotificationName(
            Self.settingsDidChangeNotification,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    private static func sharedUserDefaults() -> UserDefaults {
        UserDefaults(suiteName: sharedSuiteName) ?? .standard
    }

    private func load(from userDefaults: UserDefaults) -> AppSettings? {
        guard let data = userDefaults.data(forKey: key) else {
            return nil
        }

        do {
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            return .default
        }
    }

    private func migrateIfNeeded(_ settings: AppSettings) -> AppSettings {
        let migratedSettings = migrate(settings)
        if migratedSettings != settings {
            save(migratedSettings)
        }
        return migratedSettings
    }

    private func migrate(_ settings: AppSettings) -> AppSettings {
        guard settings.version < AppSettings.currentVersion else {
            return settings
        }

        var migratedSettings = settings
        if settings.requiredModifiers == [.option] {
            migratedSettings.requiredModifiers = AppSettings.defaultGestureModifiers
        }
        if settings.version < 6,
           settings.requiredModifiers == [.shift, .option] {
            migratedSettings.requiredModifiers = AppSettings.defaultGestureModifiers
        }
        if settings.version < 6,
           settings.shortcutPrevious == KeyboardShortcut(keyCode: 123, modifiers: [.option, .command]),
           settings.shortcutNext == KeyboardShortcut(keyCode: 124, modifiers: [.option, .command]) {
            migratedSettings.shortcutPrevious = AppSettings.default.shortcutPrevious
            migratedSettings.shortcutNext = AppSettings.default.shortcutNext
        }
        if settings.version < 7,
           settings.requiredModifiers == [.shift, .command] {
            migratedSettings.requiredModifiers = AppSettings.defaultGestureModifiers
        }
        if settings.version < 7,
           settings.shortcutPrevious == KeyboardShortcut(keyCode: 123, modifiers: [.shift, .command]),
           settings.shortcutNext == KeyboardShortcut(keyCode: 124, modifiers: [.shift, .command]) {
            migratedSettings.shortcutPrevious = AppSettings.default.shortcutPrevious
            migratedSettings.shortcutNext = AppSettings.default.shortcutNext
        }
        if settings.version < 8,
           settings.requiredModifiers == [.option, .command] {
            migratedSettings.requiredModifiers = AppSettings.defaultGestureModifiers
        }
        if settings.version < 8,
           settings.shortcutPrevious == KeyboardShortcut(keyCode: 123, modifiers: [.option, .command]),
           settings.shortcutNext == KeyboardShortcut(keyCode: 124, modifiers: [.option, .command]) {
            migratedSettings.shortcutPrevious = AppSettings.default.shortcutPrevious
            migratedSettings.shortcutNext = AppSettings.default.shortcutNext
        }
        if settings.version < 9,
           settings.requiredModifiers == [.control, .option] {
            migratedSettings.requiredModifiers = AppSettings.defaultGestureModifiers
        }
        if settings.version < 9,
           settings.shortcutPrevious == KeyboardShortcut(keyCode: 123, modifiers: [.control, .option]),
           settings.shortcutNext == KeyboardShortcut(keyCode: 124, modifiers: [.control, .option]) {
            migratedSettings.shortcutPrevious = AppSettings.default.shortcutPrevious
            migratedSettings.shortcutNext = AppSettings.default.shortcutNext
        }
        if settings.version < 10,
           settings.requiredModifiers == [.control, .option, .shift] {
            migratedSettings.requiredModifiers = AppSettings.defaultGestureModifiers
        }
        if settings.version < 10,
           settings.shortcutPrevious == KeyboardShortcut(keyCode: 123, modifiers: [.control, .option, .shift]),
           settings.shortcutNext == KeyboardShortcut(keyCode: 124, modifiers: [.control, .option, .shift]) {
            migratedSettings.shortcutPrevious = AppSettings.default.shortcutPrevious
            migratedSettings.shortcutNext = AppSettings.default.shortcutNext
        }
        if settings.version < 10 {
            migratedSettings.keyboardShortcutsEnabled = false
        }
        if settings.version < 13 {
            migratedSettings.contextPlan = ContextPlanMigration.migrate(from: settings.displaySpacePlan)
            migratedSettings.displaySpacePlan = .default
        }
        migratedSettings.version = AppSettings.currentVersion
        return migratedSettings
    }
}
