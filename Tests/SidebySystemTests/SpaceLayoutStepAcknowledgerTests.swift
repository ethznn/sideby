import XCTest
@testable import SidebySystem

final class SpaceLayoutStepAcknowledgerTests: XCTestCase {
    func testReturnsNewIndexOnceItChanges() {
        let acknowledger = SpaceLayoutStepAcknowledger(pollInterval: 0.01)
        var calls = 0

        let newIndex = acknowledger.waitForIndexChange(
            of: "ext",
            from: 2,
            timeout: 1.0
        ) {
            calls += 1
            return calls < 3 ? ["ext": 2] : ["ext": 3]
        }

        XCTAssertEqual(newIndex, 3)
    }

    func testTimesOutWhenIndexNeverChanges() {
        let acknowledger = SpaceLayoutStepAcknowledger(pollInterval: 0.01)

        let newIndex = acknowledger.waitForIndexChange(
            of: "ext",
            from: 2,
            timeout: 0.05
        ) {
            ["ext": 2]
        }

        XCTAssertNil(newIndex)
    }

    func testUnavailableReaderTimesOut() {
        let acknowledger = SpaceLayoutStepAcknowledger(pollInterval: 0.01)

        let newIndex = acknowledger.waitForIndexChange(
            of: "ext",
            from: 2,
            timeout: 0.05
        ) {
            nil
        }

        XCTAssertNil(newIndex)
    }
}
