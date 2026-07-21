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

    func testPartialRegistrationWarningSurvivesArrowSuccessAndFailureDiagnostics() {
        let successDiagnostic = diagnostic(title: "Arrow success")
        let failureDiagnostic = diagnostic(title: "Arrow failure")

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

    private var registrationWarning: DiagnosticState {
        DiagnosticState(
            severity: .warning,
            title: "Some Context shortcuts are unavailable",
            message: "Sideby could not register ⌥⇧2, ⌥⇧←. Check macOS Keyboard Shortcuts and other apps.",
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
