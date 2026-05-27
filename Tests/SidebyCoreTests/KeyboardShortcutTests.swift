import XCTest
@testable import SidebyCore

final class KeyboardShortcutTests: XCTestCase {
    func testDefaultShortcutsAreValid() {
        let issues = KeyboardShortcutValidator.issues(
            previous: AppSettings.default.shortcutPrevious,
            next: AppSettings.default.shortcutNext,
            gestureModifiers: AppSettings.default.requiredModifiers
        )

        XCTAssertTrue(issues.isEmpty)
    }

    func testDefaultInputExecutionStrategyIsModifierRelease() {
        XCTAssertEqual(AppSettings.default.inputExecutionStrategy, .modifierRelease)
    }

    func testKeyboardShortcutsDefaultToOff() {
        XCTAssertFalse(AppSettings.default.keyboardShortcutsEnabled)
    }

    func testOnlyReleaseInputExecutionStrategyIsAvailable() {
        XCTAssertEqual(InputExecutionStrategy.allCases, [.modifierRelease])
    }

    func testRejectsShortcutWithoutPrimaryModifier() {
        let issues = KeyboardShortcutValidator.issues(
            for: KeyboardShortcut(keyCode: 124, modifiers: [.shift]),
            role: .next
        )

        XCTAssertEqual(issues, [.missingPrimaryModifier(role: .next)])
    }

    func testRejectsDuplicatePreviousAndNextShortcuts() {
        let shortcut = KeyboardShortcut(keyCode: 124, modifiers: [.shift, .command])

        let issues = KeyboardShortcutValidator.issues(
            previous: shortcut,
            next: shortcut,
            gestureModifiers: [.command]
        )

        XCTAssertTrue(issues.contains(.duplicatePreviousAndNext))
    }

    func testRejectsReservedSystemShortcut() {
        let issues = KeyboardShortcutValidator.issues(
            for: KeyboardShortcut(keyCode: 124, modifiers: [.control]),
            role: .next
        )

        XCTAssertEqual(issues, [.reservedSystemShortcut(role: .next)])
    }

    func testRejectsEmptyGestureModifier() {
        let issues = KeyboardShortcutValidator.issues(
            previous: AppSettings.default.shortcutPrevious,
            next: AppSettings.default.shortcutNext,
            gestureModifiers: []
        )

        XCTAssertEqual(issues, [.emptyGestureModifier])
    }
}
