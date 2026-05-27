import XCTest
@testable import SidebyCore

final class DiagnosticsTests: XCTestCase {
    func testAccessibilityPermissionDiagnostic() {
        let decision = ModeDecision(
            isAllowed: false,
            blockReason: .accessibilityPermissionMissing,
            warnings: [],
            isExperimental: false
        )

        let states = DiagnosticRule.evaluate(decision: decision)

        XCTAssertEqual(states.first?.severity, .blocker)
        XCTAssertEqual(states.first?.title, "Accessibility permission is off")
        XCTAssertEqual(states.first?.actionLabel, "Open System Settings")
    }

    func testNoAvailableSpaceDiagnostic() {
        let decision = ModeDecision(
            isAllowed: false,
            blockReason: .noAvailableSpace,
            warnings: [],
            isExperimental: false
        )

        let states = DiagnosticRule.evaluate(decision: decision)

        XCTAssertEqual(states.first?.severity, .blocker)
        XCTAssertEqual(states.first?.title, "Only one Space is available")
        XCTAssertEqual(states.first?.actionLabel, "Add Desktop")
    }

    func testSingleDisplayWarningDiagnostic() {
        let decision = ModeDecision(
            isAllowed: true,
            blockReason: nil,
            warnings: [.singleDisplayMode],
            isExperimental: false
        )

        let states = DiagnosticRule.evaluate(decision: decision)

        XCTAssertEqual(states.first?.severity, .info)
        XCTAssertEqual(states.first?.title, "Single Display Mode")
        XCTAssertNil(states.first?.actionLabel)
    }

    func testExperimentalModeWarningDiagnostic() {
        let decision = ModeDecision(
            isAllowed: true,
            blockReason: nil,
            warnings: [.experimentalMode],
            isExperimental: true
        )

        let states = DiagnosticRule.evaluate(decision: decision)

        XCTAssertEqual(states.first?.severity, .warning)
        XCTAssertEqual(states.first?.title, "Advanced mode is experimental")
    }

    func testDiagnosticsAvoidGenericErrorMessage() {
        let decision = ModeDecision(
            isAllowed: false,
            blockReason: .noAvailableSpace,
            warnings: [],
            isExperimental: false
        )

        let messages = DiagnosticRule.evaluate(decision: decision).map(\.message)

        XCTAssertFalse(messages.contains("An error occurred."))
    }
}
