import Foundation
import XCTest
@testable import SidebyCore
@testable import SidebySystem

final class SettingsStoreTests: XCTestCase {
    func testReturnsDefaultsWhenNoSettingsAreSaved() {
        let defaults = makeDefaults()
        let store = UserDefaultsSettingsStore(userDefaults: defaults, key: "settings")

        XCTAssertEqual(store.load(), .default)
    }

    func testSavesAndLoadsSettings() {
        let defaults = makeDefaults()
        let store = UserDefaultsSettingsStore(userDefaults: defaults, key: "settings")
        var settings = AppSettings.default
        settings.mode = .shortcut
        settings.launchAtLogin = true
        settings.language = .korean

        store.save(settings)

        XCTAssertEqual(store.load(), settings)
    }

    func testFallsBackToDefaultsForCorruptData() {
        let defaults = makeDefaults()
        defaults.set(Data([0, 1, 2]), forKey: "settings")
        let store = UserDefaultsSettingsStore(userDefaults: defaults, key: "settings")

        XCTAssertEqual(store.load(), .default)
    }

    func testMigratesFallbackSettingsIntoPrimaryStore() {
        let primary = makeDefaults()
        let fallback = makeDefaults()
        let store = UserDefaultsSettingsStore(
            userDefaults: primary,
            key: "settings",
            fallbackUserDefaults: fallback
        )
        var settings = AppSettings.default
        settings.shortcutNext = KeyboardShortcut(keyCode: 14, modifiers: [.option, .command])

        let fallbackStore = UserDefaultsSettingsStore(userDefaults: fallback, key: "settings")
        fallbackStore.save(settings)

        XCTAssertEqual(store.load(), settings)
        XCTAssertEqual(UserDefaultsSettingsStore(userDefaults: primary, key: "settings").load(), settings)
    }

    func testMigratesLegacyOptionOnlyGestureToOptionShift() {
        let defaults = makeDefaults()
        let store = UserDefaultsSettingsStore(userDefaults: defaults, key: "settings")
        var legacySettings = AppSettings.default
        legacySettings.version = 1
        legacySettings.requiredModifiers = [.option]

        store.save(legacySettings)

        let migratedSettings = store.load()
        XCTAssertEqual(migratedSettings.version, AppSettings.currentVersion)
        XCTAssertEqual(migratedSettings.requiredModifiers, AppSettings.defaultGestureModifiers)
    }

    func testMigrationPreservesExistingCustomGestureModifier() {
        let defaults = makeDefaults()
        let store = UserDefaultsSettingsStore(userDefaults: defaults, key: "settings")
        var legacySettings = AppSettings.default
        legacySettings.version = 1
        legacySettings.requiredModifiers = [.control, .command]

        store.save(legacySettings)

        let migratedSettings = store.load()
        XCTAssertEqual(migratedSettings.version, AppSettings.currentVersion)
        XCTAssertEqual(migratedSettings.requiredModifiers, [.control, .command])
    }

    func testMigratesPreV6DefaultInputCombinationToOptionShift() {
        let defaults = makeDefaults()
        let store = UserDefaultsSettingsStore(userDefaults: defaults, key: "settings")
        var legacySettings = AppSettings.default
        legacySettings.version = 5
        legacySettings.requiredModifiers = [.shift, .option]
        legacySettings.shortcutPrevious = KeyboardShortcut(keyCode: 123, modifiers: [.option, .command])
        legacySettings.shortcutNext = KeyboardShortcut(keyCode: 124, modifiers: [.option, .command])

        store.save(legacySettings)

        let migratedSettings = store.load()
        XCTAssertEqual(migratedSettings.version, AppSettings.currentVersion)
        XCTAssertEqual(migratedSettings.requiredModifiers, AppSettings.defaultGestureModifiers)
        XCTAssertEqual(migratedSettings.shortcutPrevious, AppSettings.default.shortcutPrevious)
        XCTAssertEqual(migratedSettings.shortcutNext, AppSettings.default.shortcutNext)
    }

    func testMigratesCommandShiftDefaultInputCombinationToOptionShift() {
        let defaults = makeDefaults()
        let store = UserDefaultsSettingsStore(userDefaults: defaults, key: "settings")
        var legacySettings = AppSettings.default
        legacySettings.version = 6
        legacySettings.requiredModifiers = [.shift, .command]
        legacySettings.shortcutPrevious = KeyboardShortcut(keyCode: 123, modifiers: [.shift, .command])
        legacySettings.shortcutNext = KeyboardShortcut(keyCode: 124, modifiers: [.shift, .command])

        store.save(legacySettings)

        let migratedSettings = store.load()
        XCTAssertEqual(migratedSettings.version, AppSettings.currentVersion)
        XCTAssertEqual(migratedSettings.requiredModifiers, AppSettings.defaultGestureModifiers)
        XCTAssertEqual(migratedSettings.shortcutPrevious, AppSettings.default.shortcutPrevious)
        XCTAssertEqual(migratedSettings.shortcutNext, AppSettings.default.shortcutNext)
    }

    func testMigratesCommandOptionDefaultInputCombinationToOptionShift() {
        let defaults = makeDefaults()
        let store = UserDefaultsSettingsStore(userDefaults: defaults, key: "settings")
        var legacySettings = AppSettings.default
        legacySettings.version = 7
        legacySettings.requiredModifiers = [.option, .command]
        legacySettings.shortcutPrevious = KeyboardShortcut(keyCode: 123, modifiers: [.option, .command])
        legacySettings.shortcutNext = KeyboardShortcut(keyCode: 124, modifiers: [.option, .command])

        store.save(legacySettings)

        let migratedSettings = store.load()
        XCTAssertEqual(migratedSettings.version, AppSettings.currentVersion)
        XCTAssertEqual(migratedSettings.requiredModifiers, AppSettings.defaultGestureModifiers)
        XCTAssertEqual(migratedSettings.shortcutPrevious, AppSettings.default.shortcutPrevious)
        XCTAssertEqual(migratedSettings.shortcutNext, AppSettings.default.shortcutNext)
    }

    func testMigratesControlOptionDefaultInputCombinationToOptionShift() {
        let defaults = makeDefaults()
        let store = UserDefaultsSettingsStore(userDefaults: defaults, key: "settings")
        var legacySettings = AppSettings.default
        legacySettings.version = 8
        legacySettings.requiredModifiers = [.control, .option]
        legacySettings.shortcutPrevious = KeyboardShortcut(keyCode: 123, modifiers: [.control, .option])
        legacySettings.shortcutNext = KeyboardShortcut(keyCode: 124, modifiers: [.control, .option])

        store.save(legacySettings)

        let migratedSettings = store.load()
        XCTAssertEqual(migratedSettings.version, AppSettings.currentVersion)
        XCTAssertEqual(migratedSettings.requiredModifiers, AppSettings.defaultGestureModifiers)
        XCTAssertEqual(migratedSettings.shortcutPrevious, AppSettings.default.shortcutPrevious)
        XCTAssertEqual(migratedSettings.shortcutNext, AppSettings.default.shortcutNext)
    }

    func testMigratesControlOptionShiftDefaultInputCombinationToOptionShiftAndKeyboardOff() {
        let defaults = makeDefaults()
        let store = UserDefaultsSettingsStore(userDefaults: defaults, key: "settings")
        var legacySettings = AppSettings.default
        legacySettings.version = 9
        legacySettings.requiredModifiers = [.control, .option, .shift]
        legacySettings.keyboardShortcutsEnabled = true
        legacySettings.shortcutPrevious = KeyboardShortcut(keyCode: 123, modifiers: [.control, .option, .shift])
        legacySettings.shortcutNext = KeyboardShortcut(keyCode: 124, modifiers: [.control, .option, .shift])

        store.save(legacySettings)

        let migratedSettings = store.load()
        XCTAssertEqual(migratedSettings.version, AppSettings.currentVersion)
        XCTAssertEqual(migratedSettings.requiredModifiers, AppSettings.defaultGestureModifiers)
        XCTAssertEqual(migratedSettings.shortcutPrevious, AppSettings.default.shortcutPrevious)
        XCTAssertEqual(migratedSettings.shortcutNext, AppSettings.default.shortcutNext)
        XCTAssertFalse(migratedSettings.keyboardShortcutsEnabled)
    }

    func testMigratesLegacySettingsWithoutInputExecutionStrategy() throws {
        let defaults = makeDefaults()
        let store = UserDefaultsSettingsStore(userDefaults: defaults, key: "settings")
        var legacySettings = AppSettings.default
        legacySettings.version = 2
        legacySettings.inputExecutionStrategy = .modifierRelease
        let data = try JSONEncoder().encode(legacySettings)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "inputExecutionStrategy")
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        defaults.set(legacyData, forKey: "settings")

        let migratedSettings = store.load()

        XCTAssertEqual(migratedSettings.version, AppSettings.currentVersion)
        XCTAssertEqual(migratedSettings.inputExecutionStrategy, .modifierRelease)
    }

    func testMigratesLegacySettingsWithoutKeyboardShortcutsEnabled() throws {
        let defaults = makeDefaults()
        let store = UserDefaultsSettingsStore(userDefaults: defaults, key: "settings")
        var legacySettings = AppSettings.default
        legacySettings.version = 9
        let data = try JSONEncoder().encode(legacySettings)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "keyboardShortcutsEnabled")
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        defaults.set(legacyData, forKey: "settings")

        let migratedSettings = store.load()

        XCTAssertEqual(migratedSettings.version, AppSettings.currentVersion)
        XCTAssertFalse(migratedSettings.keyboardShortcutsEnabled)
    }

    func testMigratesLegacySettingsWithoutContextPlan() throws {
        let defaults = makeDefaults()
        let store = UserDefaultsSettingsStore(userDefaults: defaults, key: "settings")
        let data = try JSONEncoder().encode(AppSettings.default)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["version"] = 10
        object.removeValue(forKey: "contextPlan")
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        defaults.set(legacyData, forKey: "settings")

        let migratedSettings = store.load()

        XCTAssertEqual(migratedSettings.version, AppSettings.currentVersion)
        XCTAssertEqual(migratedSettings.contextPlan.contexts.map(\.name), ["Context 1"])
        XCTAssertEqual(migratedSettings.contextPlan.captureLimit, 4)
    }

    func testMigratesLegacySettingsWithoutDisplaySpacePlan() throws {
        let defaults = makeDefaults()
        let store = UserDefaultsSettingsStore(userDefaults: defaults, key: "settings")
        let data = try JSONEncoder().encode(AppSettings.default)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["version"] = 11
        object.removeValue(forKey: "displaySpacePlan")
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        defaults.set(legacyData, forKey: "settings")

        let migratedSettings = store.load()

        XCTAssertEqual(migratedSettings.version, AppSettings.currentVersion)
        XCTAssertEqual(migratedSettings.displaySpacePlan, .default)
    }

    func testMigratesImmediateInputExecutionStrategyToRelease() throws {
        let defaults = makeDefaults()
        let store = UserDefaultsSettingsStore(userDefaults: defaults, key: "settings")
        let data = try JSONEncoder().encode(AppSettings.default)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["version"] = 3
        object["inputExecutionStrategy"] = "immediateAppleScriptKeyUp"
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        defaults.set(legacyData, forKey: "settings")

        let migratedSettings = store.load()
        XCTAssertEqual(migratedSettings.version, AppSettings.currentVersion)
        XCTAssertEqual(migratedSettings.inputExecutionStrategy, .modifierRelease)
    }

    func testMigratesUnsupportedStoredInputExecutionStrategyToRelease() throws {
        let defaults = makeDefaults()
        let store = UserDefaultsSettingsStore(userDefaults: defaults, key: "settings")
        let data = try JSONEncoder().encode(AppSettings.default)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["inputExecutionStrategy"] = "keyboardImmediateAppleScriptKeyUp"
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        defaults.set(legacyData, forKey: "settings")

        let migratedSettings = store.load()

        XCTAssertEqual(migratedSettings.inputExecutionStrategy, .modifierRelease)
        XCTAssertEqual(migratedSettings.shortcutNext, AppSettings.default.shortcutNext)
    }

    func testMigratesLegacySettingsWithoutLanguage() throws {
        let defaults = makeDefaults()
        let store = UserDefaultsSettingsStore(userDefaults: defaults, key: "settings")
        var legacySettings = AppSettings.default
        legacySettings.version = 4
        let data = try JSONEncoder().encode(legacySettings)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "language")
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        defaults.set(legacyData, forKey: "settings")

        let migratedSettings = store.load()

        XCTAssertEqual(migratedSettings.version, AppSettings.currentVersion)
        XCTAssertEqual(migratedSettings.language, .english)
    }

    func testMigratesV12DisplaySpacePlanIntoContextPlanAndClearsLegacyLabels() throws {
        let defaults = makeDefaults()
        let store = UserDefaultsSettingsStore(userDefaults: defaults, key: "settings")
        var legacySettings = AppSettings.default
        legacySettings.version = 12
        legacySettings.displaySpacePlan = DisplaySpacePlan(
            displaySpaces: [
                DisplaySpaceSet(displayID: "built-in", spaces: [
                    DisplaySpaceSlot(order: 1, label: "Mail"),
                    DisplaySpaceSlot(order: 2, label: "Code")
                ]),
                DisplaySpaceSet(displayID: "external-lg", spaces: [
                    DisplaySpaceSlot(order: 1, label: "Calendar"),
                    DisplaySpaceSlot(order: 2, label: "Preview")
                ])
            ],
            defaultCaptureCount: 4
        )

        store.save(legacySettings)

        let migratedSettings = store.load()

        XCTAssertEqual(migratedSettings.version, AppSettings.currentVersion)
        XCTAssertEqual(migratedSettings.contextPlan.contexts.map(\.name), [
            "Mail / Calendar",
            "Code / Preview"
        ])
        XCTAssertEqual(migratedSettings.contextPlan.captureLimit, 4)
        XCTAssertEqual(migratedSettings.displaySpacePlan, .default)
    }

    func testV12ContextMigrationPreservesUnrelatedSettings() throws {
        let defaults = makeDefaults()
        let store = UserDefaultsSettingsStore(userDefaults: defaults, key: "settings")
        var legacySettings = AppSettings.default
        legacySettings.version = 12
        legacySettings.mode = .shortcut
        legacySettings.language = .korean
        legacySettings.requiredModifiers = [.control, .command]
        legacySettings.keyboardShortcutsEnabled = true
        legacySettings.shortcutPrevious = KeyboardShortcut(keyCode: 18, modifiers: [.control, .command])
        legacySettings.shortcutNext = KeyboardShortcut(keyCode: 19, modifiers: [.control, .command])
        legacySettings.horizontalThreshold = 120
        legacySettings.launchAtLogin = true
        legacySettings.displaySpacePlan = DisplaySpacePlan(
            displaySpaces: [
                DisplaySpaceSet(displayID: "built-in", spaces: [
                    DisplaySpaceSlot(order: 1, label: "Writing")
                ])
            ],
            defaultCaptureCount: 2
        )

        store.save(legacySettings)

        let migratedSettings = store.load()

        XCTAssertEqual(migratedSettings.version, AppSettings.currentVersion)
        XCTAssertEqual(migratedSettings.mode, .shortcut)
        XCTAssertEqual(migratedSettings.language, .korean)
        XCTAssertEqual(migratedSettings.requiredModifiers, [.control, .command])
        XCTAssertTrue(migratedSettings.keyboardShortcutsEnabled)
        XCTAssertEqual(
            migratedSettings.shortcutPrevious,
            KeyboardShortcut(keyCode: 18, modifiers: [.control, .command])
        )
        XCTAssertEqual(
            migratedSettings.shortcutNext,
            KeyboardShortcut(keyCode: 19, modifiers: [.control, .command])
        )
        XCTAssertEqual(migratedSettings.horizontalThreshold, 120)
        XCTAssertTrue(migratedSettings.launchAtLogin)
        XCTAssertEqual(migratedSettings.contextPlan.contexts.map(\.name), ["Writing"])
        XCTAssertEqual(migratedSettings.contextPlan.captureLimit, 2)
        XCTAssertEqual(migratedSettings.displaySpacePlan, .default)
    }

    func testMigratesV12SettingsWhenLegacyContextPlanOmitsV2Fields() throws {
        let defaults = makeDefaults()
        let store = UserDefaultsSettingsStore(userDefaults: defaults, key: "settings")
        var legacySettings = AppSettings.default
        legacySettings.version = 12
        legacySettings.language = .korean
        legacySettings.displaySpacePlan = DisplaySpacePlan(
            displaySpaces: [
                DisplaySpaceSet(displayID: "built-in", spaces: [
                    DisplaySpaceSlot(order: 1, label: "Mail")
                ]),
                DisplaySpaceSet(displayID: "external-lg", spaces: [
                    DisplaySpaceSlot(order: 1, label: "Calendar")
                ])
            ],
            defaultCaptureCount: 5
        )
        let data = try JSONEncoder().encode(legacySettings)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var legacyContextPlan = try XCTUnwrap(object["contextPlan"] as? [String: Any])
        legacyContextPlan.removeValue(forKey: "syncState")
        legacyContextPlan.removeValue(forKey: "captureLimit")
        object["contextPlan"] = legacyContextPlan
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        defaults.set(legacyData, forKey: "settings")

        let migratedSettings = store.load()

        XCTAssertEqual(migratedSettings.version, AppSettings.currentVersion)
        XCTAssertEqual(migratedSettings.language, .korean)
        XCTAssertEqual(migratedSettings.contextPlan.contexts.map(\.name), ["Mail / Calendar"])
        XCTAssertEqual(migratedSettings.contextPlan.captureLimit, 5)
        XCTAssertEqual(migratedSettings.displaySpacePlan, .default)
    }

    func testLoadingCurrentV13SettingsDoesNotRerunContextMigration() throws {
        let defaults = makeDefaults()
        let store = UserDefaultsSettingsStore(userDefaults: defaults, key: "settings")
        var currentSettings = AppSettings.default
        currentSettings.version = 13
        currentSettings.contextPlan = ContextPlan(
            contexts: [
                ContextDefinition(id: "focus", order: 1, name: "Focus"),
                ContextDefinition(id: "review", order: 2, name: "Review")
            ],
            currentContextID: "review",
            syncState: .needsSync,
            captureLimit: 2
        )
        currentSettings.displaySpacePlan = DisplaySpacePlan(
            displaySpaces: [
                DisplaySpaceSet(displayID: "built-in", spaces: [
                    DisplaySpaceSlot(order: 1, label: "Legacy label")
                ])
            ],
            defaultCaptureCount: 4
        )

        store.save(currentSettings)

        let loadedSettings = store.load()

        XCTAssertEqual(loadedSettings, currentSettings)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "SidebyTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }
}
