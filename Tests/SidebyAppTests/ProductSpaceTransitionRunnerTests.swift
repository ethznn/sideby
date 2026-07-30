import XCTest
import SidebyCore
import SidebySystem
@testable import SidebyApp

final class ProductSpaceTransitionRunnerTests: XCTestCase {
    func testCaptureProgressKeepsFirstConfirmedStepWhenSecondStepFails() {
        let first = ProductSpaceTransitionStep(
            displayID: "main",
            command: .previous,
            previousIndex: 2,
            expectedIndex: 1
        )
        var progress = ProductCaptureTransitionProgress()

        XCTAssertTrue(progress.beginOperation())
        XCTAssertEqual(progress.finishOperation(confirmedStep: first), .continueCapture)
        XCTAssertTrue(progress.beginOperation())
        XCTAssertEqual(progress.finishOperation(confirmedStep: nil), .continueCapture)
        XCTAssertEqual(progress.confirmedSteps, [first])
    }

    func testInFlightStopDefersRestoreAndKeepsConfirmedCallbackStep() {
        let step = ProductSpaceTransitionStep(
            displayID: "main",
            command: .next,
            previousIndex: 0,
            expectedIndex: 1
        )
        var progress = ProductCaptureTransitionProgress()

        XCTAssertTrue(progress.beginOperation())
        XCTAssertEqual(progress.requestStop(), .waitForInFlight)
        XCTAssertEqual(progress.finishOperation(confirmedStep: step), .restore)
        XCTAssertEqual(progress.confirmedSteps, [step])
    }

    func testRestoredMapSelectsUniqueCapturedContextOrRequiresSync() {
        let contexts = [
            ContextDefinition(
                id: "code",
                order: 1,
                name: "Code",
                displayIDs: ["main", "external"]
            ),
            ContextDefinition(
                id: "review",
                order: 2,
                name: "Review",
                displayIDs: ["main", "external"]
            )
        ]

        XCTAssertEqual(
            ProductCaptureCommitSelector.selection(
                contexts: contexts,
                restoredIndexes: ["main": 0, "external": 0],
                fallbackContextID: "review"
            ),
            .init(currentContextID: "code", needsSync: false)
        )
        XCTAssertEqual(
            ProductCaptureCommitSelector.selection(
                contexts: contexts,
                restoredIndexes: ["main": 0, "external": 1],
                fallbackContextID: "review"
            ),
            .init(currentContextID: "review", needsSync: true)
        )
    }

    func testCaptureRestoreRequestReversesSuccessfulStepsBackToCompleteInitialMap() {
        let successfulSteps = [
            ProductSpaceTransitionStep(
                displayID: "main",
                command: .previous,
                previousIndex: 2,
                expectedIndex: 1
            ),
            ProductSpaceTransitionStep(
                displayID: "external",
                command: .next,
                previousIndex: 1,
                expectedIndex: 2
            ),
            ProductSpaceTransitionStep(
                displayID: "main",
                command: .next,
                previousIndex: 1,
                expectedIndex: 2
            )
        ]

        XCTAssertEqual(
            ProductSpaceTransitionRequestBuilder.captureRestore(
                initialIndexes: ["main": 2, "external": 1],
                successfulSteps: successfulSteps
            ),
            ProductSpaceTransitionRequest(
                beforeIndexes: ["main": 2, "external": 2],
                steps: [
                    .init(displayID: "main", command: .previous, previousIndex: 2, expectedIndex: 1),
                    .init(displayID: "external", command: .previous, previousIndex: 2, expectedIndex: 1),
                    .init(displayID: "main", command: .next, previousIndex: 1, expectedIndex: 2)
                ],
                finalExpectedIndexes: ["main": 2, "external": 1]
            )
        )
    }

    func testRelativeRequestObservesCompleteMapWhileOnlyMovingTargets() {
        XCTAssertEqual(
            ProductSpaceTransitionRequestBuilder.relative(
                displays: [
                    .init(displayID: "main", spaceCount: 3, currentSpaceIndex: 0),
                    .init(displayID: "external", spaceCount: 5, currentSpaceIndex: 3)
                ],
                targetDisplayIDs: ["main"],
                command: .next
            ),
            ProductRelativeTransitionRequest.request(
                ProductSpaceTransitionRequest(
                    beforeIndexes: ["main": 0, "external": 3],
                    steps: [
                        .init(displayID: "main", command: .next, previousIndex: 0, expectedIndex: 1)
                    ],
                    finalExpectedIndexes: ["main": 1, "external": 3]
                )
            )
        )
    }

    func testRelativeRequestReportsAllTargetsAtBoundaryWithoutBuildingZeroStepTransition() {
        XCTAssertEqual(
            ProductSpaceTransitionRequestBuilder.relative(
                displays: [
                    .init(displayID: "main", spaceCount: 3, currentSpaceIndex: 2),
                    .init(displayID: "external", spaceCount: 2, currentSpaceIndex: 1)
                ],
                targetDisplayIDs: ["main", "external"],
                command: .next
            ),
            .boundary
        )
    }

    func testStationaryRequestKeepsCompleteMapForStableVerification() {
        XCTAssertEqual(
            ProductSpaceTransitionRequestBuilder.stationary(
                displays: [
                    .init(displayID: "main", spaceCount: 3, currentSpaceIndex: 1),
                    .init(displayID: "external", spaceCount: 2, currentSpaceIndex: 0)
                ]
            ),
            ProductSpaceTransitionRequest(
                beforeIndexes: ["main": 1, "external": 0],
                steps: [],
                finalExpectedIndexes: ["main": 1, "external": 0]
            )
        )
    }

    func testOneAdjacentStepPostsOnceAndReturnsExactStableMap() {
        let executors = RecordingExecutors()
        let runner = makeRunner(
            snapshots: [
                ["main": 1], ["main": 1],
                ["main": 1], ["main": 1]
            ],
            executors: executors
        )

        XCTAssertEqual(
            runner.run(.init(
                beforeIndexes: ["main": 0],
                steps: [.init(displayID: "main", command: .next, previousIndex: 0, expectedIndex: 1)],
                finalExpectedIndexes: ["main": 1]
            )),
            .success(["main": 1])
        )
        XCTAssertEqual(executors.commandsByDisplay, ["main": [.next]])
    }

    func testIntermediateStepsAcknowledgeExactlyWhileOnlyFinalMapUsesStabilityWindow() {
        let executors = RecordingExecutors()
        let harness = ScriptedLayoutHarness([
            ["main": 1],
            ["main": 2],
            ["main": 2], ["main": 2], ["main": 2], ["main": 2], ["main": 2]
        ])
        let runner = ProductSpaceTransitionRunner(
            makeExecutor: { displayID in executors.executor(for: displayID) },
            verifier: harness.makeVerifier(
                pollInterval: 0.25,
                stabilityDuration: 0.75,
                maximumPolls: 4
            )
        )

        XCTAssertEqual(
            runner.run(.init(
                beforeIndexes: ["main": 0],
                steps: [
                    .init(displayID: "main", command: .next, previousIndex: 0, expectedIndex: 1),
                    .init(displayID: "main", command: .next, previousIndex: 1, expectedIndex: 2)
                ],
                finalExpectedIndexes: ["main": 2]
            )),
            .success(["main": 2])
        )
        XCTAssertEqual(executors.commandsByDisplay, ["main": [.next, .next]])
        XCTAssertEqual(harness.elapsedTime, 0.75, accuracy: 0.000_001)
    }

    func testMultiStepStopsPostingAfterFirstFailure() {
        let executors = RecordingExecutors(results: [true, false])
        let runner = makeRunner(
            snapshots: [["main": 1], ["main": 1]],
            executors: executors
        )

        XCTAssertEqual(
            runner.run(.init(
                beforeIndexes: ["main": 0],
                steps: [
                    .init(displayID: "main", command: .next, previousIndex: 0, expectedIndex: 1),
                    .init(displayID: "main", command: .next, previousIndex: 1, expectedIndex: 2),
                    .init(displayID: "main", command: .next, previousIndex: 2, expectedIndex: 3)
                ],
                finalExpectedIndexes: ["main": 3]
            )),
            failure(
                .postRejected(displayID: "main", command: .next),
                confirmedIndexes: ["main": 1],
                mayHaveMoved: true
            )
        )
        XCTAssertEqual(executors.commandsByDisplay, ["main": [.next, .next]])
    }

    func testFailedMultiStepReportsConfirmedProgressAndPossibleMovement() {
        let executors = RecordingExecutors(results: [true, false])
        let runner = makeRunner(
            snapshots: [["main": 1]],
            executors: executors
        )

        XCTAssertEqual(
            runner.run(.init(
                beforeIndexes: ["main": 0],
                steps: [
                    .init(displayID: "main", command: .next, previousIndex: 0, expectedIndex: 1),
                    .init(displayID: "main", command: .next, previousIndex: 1, expectedIndex: 2)
                ],
                finalExpectedIndexes: ["main": 2]
            )),
            .failure(
                .postRejected(displayID: "main", command: .next),
                progress: .init(
                    confirmedIndexes: ["main": 1],
                    mayHaveMoved: true
                )
            )
        )
    }

    func testVerifierFailuresRejectUnreadableWrongDirectionUnexpectedDisplayAndReboundLayouts() {
        let request = ProductSpaceTransitionRequest(
            beforeIndexes: ["main": 0, "external": 0],
            steps: [.init(displayID: "main", command: .next, previousIndex: 0, expectedIndex: 1)],
            finalExpectedIndexes: ["main": 1, "external": 0]
        )

        for (snapshots, expected) in [
            ([nil], failure(.verification(.unreadableLayout), confirmedIndexes: ["main": 0, "external": 0], mayHaveMoved: true)),
            ([["main": 2, "external": 0]], failure(.verification(.wrongDirection), confirmedIndexes: ["main": 0, "external": 0], mayHaveMoved: true)),
            ([["main": 1, "external": 1]], failure(.verification(.unexpectedDisplayChange(displayID: "external")), confirmedIndexes: ["main": 0, "external": 0], mayHaveMoved: true)),
            ([["main": 1, "external": 0], ["main": 1, "external": 0], ["main": 1, "external": 0], ["main": 0, "external": 0]], failure(.verification(.unstableTransition), confirmedIndexes: ["main": 1, "external": 0], mayHaveMoved: true))
        ] {
            XCTAssertEqual(
                makeRunner(
                    snapshots: snapshots,
                    executors: RecordingExecutors(),
                    stabilityDuration: 0.01
                ).run(request),
                expected
            )
        }
    }

    func testExecutorFailureFailsEvenWhenTheLayoutAlreadyMoved() {
        XCTAssertEqual(
            makeRunner(
                snapshots: [["main": 1], ["main": 1]],
                executors: RecordingExecutors(results: [false])
            ).run(.init(
                beforeIndexes: ["main": 0],
                steps: [.init(displayID: "main", command: .next, previousIndex: 0, expectedIndex: 1)],
                finalExpectedIndexes: ["main": 1]
            )),
            failure(
                .postRejected(displayID: "main", command: .next),
                confirmedIndexes: ["main": 0],
                mayHaveMoved: true
            )
        )
    }

    func testNoStepOnlySucceedsWhenReadableMapMatches() {
        let request = ProductSpaceTransitionRequest(
            beforeIndexes: ["main": 1],
            steps: [],
            finalExpectedIndexes: ["main": 1]
        )

        XCTAssertEqual(
            makeRunner(snapshots: [["main": 1], ["main": 1]], executors: RecordingExecutors()).run(request),
            .success(["main": 1])
        )
        XCTAssertEqual(
            makeRunner(snapshots: [nil], executors: RecordingExecutors()).run(request),
            failure(
                .verification(.unreadableLayout),
                confirmedIndexes: ["main": 1],
                mayHaveMoved: false
            )
        )
    }

    private func makeRunner(
        snapshots: [[String: Int]?],
        executors: RecordingExecutors,
        pollInterval: TimeInterval = 0.01,
        stabilityDuration: TimeInterval = 0,
        maximumPolls: Int = 3
    ) -> ProductSpaceTransitionRunner {
        let harness = ScriptedLayoutHarness(snapshots)
        return ProductSpaceTransitionRunner(
            makeExecutor: { displayID in executors.executor(for: displayID) },
            verifier: harness.makeVerifier(
                pollInterval: pollInterval,
                stabilityDuration: stabilityDuration,
                maximumPolls: maximumPolls
            )
        )
    }

    private func failure(
        _ failure: ProductSpaceTransitionFailure,
        confirmedIndexes: [String: Int],
        mayHaveMoved: Bool
    ) -> ProductSpaceTransitionResult {
        .failure(
            failure,
            progress: .init(
                confirmedIndexes: confirmedIndexes,
                mayHaveMoved: mayHaveMoved
            )
        )
    }
}

private final class RecordingExecutors: @unchecked Sendable {
    private var results: [Bool]
    private(set) var commandsByDisplay: [String: [SwitchCommand]] = [:]

    init(results: [Bool] = []) {
        self.results = results
    }

    func executor(for displayID: String) -> any SpaceCommandExecuting {
        RecordingExecutor { [self] command in
            commandsByDisplay[displayID, default: []].append(command)
            return results.isEmpty ? true : results.removeFirst()
        }
    }
}

private struct RecordingExecutor: SpaceCommandExecuting {
    let executeCommand: @Sendable (SwitchCommand) -> Bool

    func execute(_ command: SwitchCommand) -> Bool {
        executeCommand(command)
    }
}

private final class ScriptedLayoutHarness: @unchecked Sendable {
    private let snapshots: [[String: Int]?]
    private var offset = 0
    private var time: TimeInterval = 0

    var elapsedTime: TimeInterval {
        time
    }

    init(_ snapshots: [[String: Int]?]) {
        self.snapshots = snapshots
    }

    func makeVerifier(
        pollInterval: TimeInterval = 0.01,
        stabilityDuration: TimeInterval = 0,
        maximumPolls: Int = 3
    ) -> StableSpaceLayoutVerifier {
        StableSpaceLayoutVerifier(
            pollInterval: pollInterval,
            stabilityDuration: stabilityDuration,
            maximumPolls: maximumPolls,
            dependencies: .init(
                now: { [self] in time },
                sleep: { [self] interval in time += interval },
                readIndexes: { [self] in
                    let index = min(offset, snapshots.count - 1)
                    offset += 1
                    return snapshots[index]
                }
            )
        )
    }
}
