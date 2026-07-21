import XCTest
@testable import SidebyCore
@testable import SidebyUI

final class FloatingMenuDiagnosticsContentTests: XCTestCase {
    func testPartialRegistrationFailureExposesExactShortcutWarning() {
        let diagnostics = ContextKeyboardDiagnosticMerger.mergingRegistrationFailures(
            [.activate(position: 2), .move(.previous)],
            into: [],
            strings: SBSStrings(language: .english)
        )

        XCTAssertEqual(
            FloatingMenuDiagnosticsContent.section(
                for: diagnostics,
                strings: SBSStrings(language: .english)
            ),
            FloatingMenuDiagnosticsSection(
                items: [
                    FloatingMenuDiagnosticItem(
                        severity: .warning,
                        title: "Some Context shortcuts are unavailable",
                        message: "Sideby could not register ⌥⇧2, ⌥⇧←. Check macOS Keyboard Shortcuts and other apps."
                    )
                ]
            )
        )
    }

    func testTotalRegistrationFailureExposesEveryShortcut() {
        let failedCommands = ContextKeyboardShortcutCatalog.bindings.map(\.command)
        let diagnostics = ContextKeyboardDiagnosticMerger.mergingRegistrationFailures(
            failedCommands,
            into: [],
            strings: SBSStrings(language: .english)
        )

        XCTAssertEqual(
            FloatingMenuDiagnosticsContent.section(
                for: diagnostics,
                strings: SBSStrings(language: .english)
            )?.items.first?.message,
            "Sideby could not register ⌥⇧1, ⌥⇧2, ⌥⇧3, ⌥⇧4, ⌥⇧5, ⌥⇧6, ⌥⇧7, ⌥⇧8, ⌥⇧9, ⌥⇧0, ⌥⇧←, ⌥⇧→. Check macOS Keyboard Shortcuts and other apps."
        )
    }

    func testEmptyDiagnosticsHideSection() {
        XCTAssertNil(
            FloatingMenuDiagnosticsContent.section(
                for: [],
                strings: SBSStrings(language: .english)
            )
        )
    }

    func testGeneralDiagnosticsRemainVisibleAndUseCurrentLocalization() {
        let diagnostic = DiagnosticState(
            severity: .blocker,
            title: "Only one Space is available",
            message: "Add another Desktop in Mission Control before switching contexts.",
            actionLabel: "Add Desktop"
        )

        XCTAssertEqual(
            FloatingMenuDiagnosticsContent.section(
                for: [diagnostic],
                strings: SBSStrings(language: .korean)
            ),
            FloatingMenuDiagnosticsSection(
                items: [
                    FloatingMenuDiagnosticItem(
                        severity: .blocker,
                        title: "사용 가능한 Space가 하나뿐입니다",
                        message: "컨텍스트를 전환하기 전에 Mission Control에서 데스크탑을 하나 더 추가하세요."
                    )
                ]
            )
        )
    }
}
