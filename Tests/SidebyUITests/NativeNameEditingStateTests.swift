import XCTest
@testable import SidebyUI

final class NativeNameEditingStateTests: XCTestCase {
    func testFocusedDraftSurvivesDomainWhitespaceNormalization() {
        var state = NativeNameEditingState(value: "Payment")
        state.isFocused = true
        state.edit("Payment ")
        state.receiveExternalValue("Payment")
        XCTAssertEqual(state.draft, "Payment ")
        state.edit(state.draft + "Review")
        XCTAssertEqual(state.draft, "Payment Review")
    }

    func testUnfocusedDraftReceivesExternalRename() {
        var state = NativeNameEditingState(value: "Payment")
        state.receiveExternalValue("PR Review")
        XCTAssertEqual(state.draft, "PR Review")
    }

    func testBlurReconcilesLatestNormalizedValueEvenWithoutAnotherModelChange() {
        var state = NativeNameEditingState(value: "Payment")
        state.isFocused = true
        state.edit("Payment ")
        state.receiveExternalValue("Payment")
        state.isFocused = false
        XCTAssertEqual(state.draft, "Payment")
    }

    func testNewIdentityBufferStartsWithItsOwnValue() {
        var state = NativeNameEditingState(value: "Payment")
        state.isFocused = true
        state.edit("Payment ")
        state = NativeNameEditingState(value: "Review")
        XCTAssertEqual(state.draft, "Review")
        XCTAssertFalse(state.isFocused)
    }
}
