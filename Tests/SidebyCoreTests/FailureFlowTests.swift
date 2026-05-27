import XCTest
@testable import SidebyCore

final class FailureFlowTests: XCTestCase {
    func testDisplayConfigurationChangedHasActionableDiagnostic() {
        let diagnostic = FailureFlowResolver().diagnostic(for: .displayConfigurationChanged)

        XCTAssertEqual(diagnostic.severity, .warning)
        XCTAssertEqual(diagnostic.title, "Display layout changed")
        XCTAssertEqual(diagnostic.actionLabel, "Review Displays")
    }

    func testSwitchExecutionFailedDoesNotUseGenericErrorCopy() {
        let diagnostic = FailureFlowResolver().diagnostic(for: .switchExecutionFailed)

        XCTAssertNotEqual(diagnostic.message, "An error occurred.")
        XCTAssertEqual(diagnostic.title, "Context did not switch")
    }
}
