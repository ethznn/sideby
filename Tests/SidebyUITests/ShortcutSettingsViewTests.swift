import XCTest
@testable import SidebyCore
@testable import SidebyUI

final class ShortcutSettingsViewTests: XCTestCase {
    func testFormatsDefaultShortcutCaps() {
        XCTAssertEqual(
            KeyboardShortcutFormatter.shortcutText(AppSettings.default.shortcutNext),
            "⌥⇧→"
        )
    }

    func testFormatsGestureModifiers() {
        XCTAssertEqual(
            KeyboardShortcutFormatter.modifierText([.control, .option]),
            "⌃⌥"
        )
    }

    func testFormatsDefaultGestureModifiers() {
        XCTAssertEqual(
            KeyboardShortcutFormatter.modifierText(AppSettings.default.requiredModifiers),
            "⌥⇧"
        )
    }

    func testLocalizesReleaseStrategy() {
        let strings = SBSStrings(language: .english)

        XCTAssertEqual(strings.strategyTitle(.modifierRelease), "Release")
    }

    func testFallsBackToKeyCodeForUnknownKey() {
        XCTAssertEqual(KeyboardShortcutFormatter.keyCap(for: 999), "#999")
    }

    func testLocalizesLanguageNames() {
        let korean = SBSStrings(language: .korean)

        XCTAssertEqual(korean.languageName(.english), "영어")
        XCTAssertEqual(korean.languageName(.korean), "한국어")
    }

    func testLocalizesDisplaySummary() {
        let korean = SBSStrings(language: .korean)

        XCTAssertEqual(korean.selectedDisplaySummary(selected: 2, total: 2), "디스플레이 2개 모두 선택됨")
        XCTAssertEqual(korean.selectedDisplaySummary(selected: 1, total: 2), "디스플레이 1/2개 선택됨")
    }

    func testPostEventPermissionActionUsesSwitchingAccessCopy() {
        XCTAssertEqual(SBSStrings(language: .english).enablePostEvents, "Check Switching Access")
        XCTAssertEqual(SBSStrings(language: .korean).enablePostEvents, "화면 전환 권한 확인")
    }

    func testLocalizesAutomationPermissionFeedbackAction() {
        let english = SBSStrings(language: .english)
        let korean = SBSStrings(language: .korean)

        XCTAssertEqual(english.permissionRequestActionTitle(.openAutomationSettings), "Automation Settings")
        XCTAssertEqual(korean.permissionRequestActionTitle(.openAutomationSettings), "자동화 설정")
    }

    func testOnboardingCompletionActionOpensSettings() {
        XCTAssertEqual(SBSStrings(language: .english).onboardingCompletionActionTitle, "Open Settings")
        XCTAssertEqual(SBSStrings(language: .korean).onboardingCompletionActionTitle, "설정 열기")
    }
}
