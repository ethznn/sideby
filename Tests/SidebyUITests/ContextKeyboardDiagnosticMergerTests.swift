import XCTest
@testable import SidebyCore
@testable import SidebyUI

final class ContextKeyboardDiagnosticMergerTests: XCTestCase {
    private let failedCommands: [ContextKeyboardCommand] = [
        .activate(position: 2),
        .move(.previous)
    ]

    func testPartialRegistrationWarningSurvivesNoMoveNumberActivation() {
        XCTAssertEqual(
            ContextKeyboardDiagnosticMerger.mergingRegistrationFailures(
                failedCommands,
                into: [],
                strings: SBSStrings(language: .english)
            ),
            [registrationWarning]
        )
    }

    func testPartialRegistrationWarningSurvivesNumberActivationResultDiagnostics() {
        let activationDiagnostic = diagnostic(title: "Activation result")

        XCTAssertEqual(
            ContextKeyboardDiagnosticMerger.mergingRegistrationFailures(
                failedCommands,
                into: [activationDiagnostic],
                strings: SBSStrings(language: .english)
            ),
            [activationDiagnostic, registrationWarning]
        )
    }

    func testPartialRegistrationWarningSurvivesContextMoveSuccessAndFailureDiagnostics() {
        let successDiagnostic = diagnostic(title: "Context move success")
        let failureDiagnostic = diagnostic(title: "Context move failure")

        XCTAssertEqual(
            ContextKeyboardDiagnosticMerger.mergingRegistrationFailures(
                failedCommands,
                into: [successDiagnostic],
                strings: SBSStrings(language: .english)
            ),
            [successDiagnostic, registrationWarning]
        )
        XCTAssertEqual(
            ContextKeyboardDiagnosticMerger.mergingRegistrationFailures(
                failedCommands,
                into: [failureDiagnostic],
                strings: SBSStrings(language: .english)
            ),
            [failureDiagnostic, registrationWarning]
        )
    }

    func testExistingRegistrationWarningIsNotDuplicated() {
        XCTAssertEqual(
            ContextKeyboardDiagnosticMerger.mergingRegistrationFailures(
                failedCommands,
                into: [registrationWarning],
                strings: SBSStrings(language: .english)
            ),
            [registrationWarning]
        )
    }

    func testEmptyFailureListReturnsOriginalDiagnostics() {
        let original = [diagnostic(title: "Original")]

        XCTAssertEqual(
            ContextKeyboardDiagnosticMerger.mergingRegistrationFailures(
                [],
                into: original,
                strings: SBSStrings(language: .english)
            ),
            original
        )
    }

    func testDiagnosticsUseCurrentLanguageWithoutAccumulatingStoredWarningWhileInputIsOff() {
        let runtimeDiagnostics = [diagnostic(title: "Runtime")]

        let english = ContextKeyboardDiagnosticMerger.diagnostics(
            runtimeDiagnostics: runtimeDiagnostics,
            failedCommands: failedCommands,
            strings: SBSStrings(language: .english)
        )
        let korean = ContextKeyboardDiagnosticMerger.diagnostics(
            runtimeDiagnostics: runtimeDiagnostics,
            failedCommands: failedCommands,
            strings: SBSStrings(language: .korean)
        )

        XCTAssertEqual(english.count, 2)
        XCTAssertEqual(english.last?.title, "Some Context shortcuts are unavailable")
        XCTAssertEqual(korean.count, 2)
        XCTAssertEqual(korean.last?.title, "일부 Context 단축키를 사용할 수 없습니다")
        XCTAssertFalse(korean.contains { $0.title == "Some Context shortcuts are unavailable" })
    }

    private var registrationWarning: DiagnosticState {
        DiagnosticState(
            severity: .warning,
            title: "Some Context shortcuts are unavailable",
            message: "Sideby could not register ⌥⇧2, ⌥⇧<. Check macOS Keyboard Shortcuts and other apps.",
            actionLabel: nil
        )
    }

    private func diagnostic(title: String) -> DiagnosticState {
        DiagnosticState(
            severity: .warning,
            title: title,
            message: "Message",
            actionLabel: nil
        )
    }
}
