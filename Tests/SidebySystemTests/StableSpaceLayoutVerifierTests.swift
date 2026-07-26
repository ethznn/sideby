import XCTest
@testable import SidebySystem

final class StableSpaceLayoutVerifierTests: XCTestCase {
    func testExpectedMapMustRemainStableForFullWindow() {
        let harness = ScriptedLayoutHarness([
            ["built-in": 0, "external": 0],
            ["built-in": 1, "external": 0],
            ["built-in": 1, "external": 0],
            ["built-in": 1, "external": 0]
        ])
        let verifier = harness.makeVerifier(
            pollInterval: 0.025,
            stabilityDuration: 0.075,
            maximumPolls: 8
        )

        XCTAssertEqual(
            verifier.waitForExpectedThenStable(
                previous: ["built-in": 0, "external": 0],
                expected: ["built-in": 1, "external": 0],
                changedDisplayIDs: ["built-in"]
            ),
            .success(["built-in": 1, "external": 0])
        )
    }

    func testDifferentIndexOnChangedDisplayFailsAsWrongDirection() {
        let harness = ScriptedLayoutHarness([["built-in": 2, "external": 0]])

        XCTAssertEqual(
            harness.makeVerifier().waitForExpectedThenStable(
                previous: ["built-in": 0, "external": 0],
                expected: ["built-in": 1, "external": 0],
                changedDisplayIDs: ["built-in"]
            ),
            .failure(.wrongDirection)
        )
    }

    func testMovementOnUnchangedDisplayFails() {
        let harness = ScriptedLayoutHarness([["built-in": 0, "external": 1]])

        XCTAssertEqual(
            harness.makeVerifier().waitForExpectedThenStable(
                previous: ["built-in": 0, "external": 0],
                expected: ["built-in": 1, "external": 0],
                changedDisplayIDs: ["built-in"]
            ),
            .failure(.unexpectedDisplayChange(displayID: "external"))
        )
    }

    func testUnreadableLayoutIsNotBoundary() {
        let harness = ScriptedLayoutHarness([nil])

        XCTAssertEqual(
            harness.makeVerifier().waitForExpectedThenStable(
                previous: ["built-in": 0],
                expected: ["built-in": 1],
                changedDisplayIDs: ["built-in"]
            ),
            .failure(.unreadableLayout)
        )
    }

    func testInitialPhaseTimesOutWhenExpectedMapNeverAppears() {
        let harness = ScriptedLayoutHarness([["built-in": 0]])

        XCTAssertEqual(
            harness.makeVerifier(
                pollInterval: 0.025,
                stabilityDuration: 0.075,
                maximumPolls: 4
            ).waitForExpectedThenStable(
                previous: ["built-in": 0],
                expected: ["built-in": 1],
                changedDisplayIDs: ["built-in"]
            ),
            .failure(.timeout)
        )
    }

    func testReboundDuringStabilityFails() {
        let harness = ScriptedLayoutHarness([
            ["built-in": 1],
            ["built-in": 1],
            ["built-in": 0]
        ])

        XCTAssertEqual(
            harness.makeVerifier().waitForExpectedThenStable(
                previous: ["built-in": 0],
                expected: ["built-in": 1],
                changedDisplayIDs: ["built-in"]
            ),
            .failure(.unstableTransition)
        )
    }

    func testExpectedSnapshotAtExactStabilityDeadlineSucceeds() {
        let harness = ScriptedLayoutHarness([["built-in": 1]])

        XCTAssertEqual(
            harness.makeVerifier(
                pollInterval: 0.025,
                stabilityDuration: 0.05,
                maximumPolls: 3
            ).waitForExpectedThenStable(
                previous: ["built-in": 0],
                expected: ["built-in": 1],
                changedDisplayIDs: ["built-in"]
            ),
            .success(["built-in": 1])
        )
    }

    func testPollingIsBoundedWhenClockDoesNotAdvance() {
        let harness = ScriptedLayoutHarness([["built-in": 0]], advancesClockWhenSleeping: false)

        XCTAssertEqual(
            harness.makeVerifier(maximumPolls: 2).waitForExpectedThenStable(
                previous: ["built-in": 0],
                expected: ["built-in": 1],
                changedDisplayIDs: ["built-in"]
            ),
            .failure(.timeout)
        )
        XCTAssertEqual(harness.readCount, 2)
    }
}

private final class ScriptedLayoutHarness: @unchecked Sendable {
    private let snapshots: [[String: Int]?]
    private let advancesClockWhenSleeping: Bool
    private var snapshotOffset = 0
    private var currentTime: TimeInterval = 0
    private(set) var readCount = 0

    init(_ snapshots: [[String: Int]?], advancesClockWhenSleeping: Bool = true) {
        self.snapshots = snapshots
        self.advancesClockWhenSleeping = advancesClockWhenSleeping
    }

    func makeVerifier(
        pollInterval: TimeInterval = 0.025,
        stabilityDuration: TimeInterval = 0.075,
        maximumPolls: Int = 8
    ) -> StableSpaceLayoutVerifier {
        StableSpaceLayoutVerifier(
            pollInterval: pollInterval,
            stabilityDuration: stabilityDuration,
            maximumPolls: maximumPolls,
            dependencies: StableSpaceLayoutVerifierDependencies(
                now: { [self] in currentTime },
                sleep: { [self] interval in
                    if advancesClockWhenSleeping {
                        currentTime += interval
                    }
                },
                readIndexes: { [self] in
                    readCount += 1
                    let offset = min(snapshotOffset, snapshots.count - 1)
                    snapshotOffset += 1
                    return snapshots[offset]
                }
            )
        )
    }
}
