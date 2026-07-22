import XCTest
@testable import SidebyCore
@testable import SidebyUI

final class ShortcutSettingsViewTests: XCTestCase {
    func testFormatsShiftedCommaAndPeriodAsAngleBrackets() {
        XCTAssertEqual(
            KeyboardShortcutFormatter.shortcutText(
                SBSKeyboardShortcut(keyCode: 43, modifiers: [.option, .shift])
            ),
            "⌥⇧<"
        )
        XCTAssertEqual(
            KeyboardShortcutFormatter.shortcutText(
                SBSKeyboardShortcut(keyCode: 47, modifiers: [.option, .shift])
            ),
            "⌥⇧>"
        )
        XCTAssertEqual(KeyboardShortcutFormatter.keyCap(for: 43), ",")
        XCTAssertEqual(KeyboardShortcutFormatter.keyCap(for: 47), ".")
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

    func testLocalizesFixedContextKeyboardLayer() {
        let english = SBSStrings(language: .english)
        let korean = SBSStrings(language: .korean)

        XCTAssertEqual(english.contextKeyboardNumberHint, "Jump to Context: ⌥⇧1 … ⌥⇧9, ⌥⇧0")
        XCTAssertEqual(korean.contextKeyboardNumberHint, "Context 바로 이동: ⌥⇧1 … ⌥⇧9, ⌥⇧0")
        XCTAssertEqual(english.contextKeyboardArrowHint, "Previous / Next Context: ⌥⇧< / ⌥⇧>")
        XCTAssertEqual(korean.contextKeyboardArrowHint, "이전 / 다음 Context: ⌥⇧< / ⌥⇧>")
        XCTAssertEqual(english.sidebyToggleOffHUD, "Sideby is turned off")
        XCTAssertEqual(korean.sidebyToggleOffHUD, "Sideby 토글이 꺼져 있습니다")
        XCTAssertEqual(english.missingContextHUD(position: 10), "Context 10 does not exist")
        XCTAssertEqual(korean.missingContextHUD(position: 7), "Context 7이 없습니다")
    }

    func testFixedKeyboardFeedbackUsesCompactHUD() {
        let presenter = HUDPresenter()

        XCTAssertEqual(
            presenter.stateForSidebyToggleOff(strings: SBSStrings(language: .korean)),
            HUDPresentationState(text: "Sideby 토글이 꺼져 있습니다", isCompact: true)
        )
        XCTAssertEqual(
            presenter.stateForMissingContext(
                position: 7,
                strings: SBSStrings(language: .english)
            ),
            HUDPresentationState(text: "Context 7 does not exist", isCompact: true)
        )
    }

    func testLocalizesFixedKeyboardRegistrationFailure() {
        let english = SBSStrings(language: .english)
        let korean = SBSStrings(language: .korean)

        XCTAssertEqual(english.contextKeyboardRegistrationTitle, "Some Context shortcuts are unavailable")
        XCTAssertEqual(
            english.contextKeyboardRegistrationMessage(shortcuts: "⌥⇧2, ⌥⇧<"),
            "Sideby could not register ⌥⇧2, ⌥⇧<. Check macOS Keyboard Shortcuts and other apps."
        )
        XCTAssertEqual(korean.contextKeyboardRegistrationTitle, "일부 Context 단축키를 사용할 수 없습니다")
        XCTAssertEqual(
            korean.contextKeyboardRegistrationMessage(shortcuts: "⌥⇧2, ⌥⇧<"),
            "Sideby가 ⌥⇧2, ⌥⇧<을 등록하지 못했습니다. macOS 키보드 단축키와 다른 앱을 확인하세요."
        )
    }

    func testInputAndOnboardingCopyDescribeFixedKeyboardLayer() {
        let english = SBSStrings(language: .english)
        let korean = SBSStrings(language: .korean)

        XCTAssertEqual(
            english.inputSubtitle,
            "Set the gesture modifier and review fixed Context keyboard controls."
        )
        XCTAssertEqual(
            korean.contextKeyboardLayerHint,
            "Option + Shift를 누른 채 숫자 또는 < / >를 사용할 수 있습니다."
        )
    }

    func testLocalizesFixedKeyboardSetupStatusInKorean() {
        XCTAssertEqual(
            SBSStrings(language: .korean).setupViewStatus(
                "Use Option + Shift with horizontal scroll, a Context number, or < / >."
            ),
            "Option + Shift와 가로 스크롤, Context 숫자 또는 < / >를 사용하세요."
        )
    }
}
