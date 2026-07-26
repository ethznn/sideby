import XCTest
@testable import SidebySystem

final class SpaceLayoutStepAcknowledgerTests: XCTestCase {
    func testReturnsNewIndexOnceItChanges() {
        let acknowledger = SpaceLayoutStepAcknowledger(pollInterval: 0.01)

        let newIndex = acknowledger.waitForIndexChange(
            of: "ext",
            from: 2,
            timeout: 0
        ) {
            ["ext": 3]
        }

        XCTAssertEqual(newIndex, 3)
    }

    func testTimesOutWhenIndexNeverChanges() {
        let acknowledger = SpaceLayoutStepAcknowledger(pollInterval: 0.01)

        let newIndex = acknowledger.waitForIndexChange(
            of: "ext",
            from: 2,
            timeout: 0
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
            timeout: 0
        ) {
            nil
        }

        XCTAssertNil(newIndex)
    }

    func testExpectedIndexReturnsCompleteExpectedSnapshot() {
        let acknowledger = SpaceLayoutStepAcknowledger()

        XCTAssertEqual(
            acknowledger.waitForExpectedIndex(
                of: "ext",
                from: 2,
                expectedIndex: 3,
                timeout: 0
            ) {
                ["built-in": 1, "ext": 3]
            },
            .success(["built-in": 1, "ext": 3])
        )
    }

    func testExpectedIndexClassifiesTerminalSnapshots() {
        let acknowledger = SpaceLayoutStepAcknowledger()

        XCTAssertEqual(
            acknowledger.waitForExpectedIndex(
                of: "ext",
                from: 2,
                expectedIndex: 3,
                timeout: 0
            ) { ["ext": 2] },
            .failure(.timeout)
        )
        XCTAssertEqual(
            acknowledger.waitForExpectedIndex(
                of: "ext",
                from: 2,
                expectedIndex: 3,
                timeout: 0
            ) { ["ext": 1] },
            .failure(.wrongDirection)
        )
        XCTAssertEqual(
            acknowledger.waitForExpectedIndex(
                of: "ext",
                from: 2,
                expectedIndex: 3,
                timeout: 0
            ) { nil },
            .failure(.unreadableLayout)
        )
    }

    func testExpectedIndexFailsImmediatelyWhenWrongDirectionPrecedesExpectedIndex() {
        let acknowledger = SpaceLayoutStepAcknowledger(pollInterval: 0.001)
        var snapshots = [["ext": 1], ["ext": 3]]

        let result = acknowledger.waitForExpectedIndex(
            of: "ext",
            from: 2,
            expectedIndex: 3,
            timeout: 1
        ) {
            snapshots.removeFirst()
        }

        XCTAssertEqual(result, .failure(.wrongDirection))
        XCTAssertEqual(snapshots, [["ext": 3]])
    }
}
