import SidebyCore
import SidebySystem

struct ProductSpaceTransitionStep: Equatable, Sendable {
    let displayID: String
    let command: SwitchCommand
    let previousIndex: Int
    let expectedIndex: Int

    init(displayID: String, command: SwitchCommand, previousIndex: Int, expectedIndex: Int) {
        self.displayID = displayID
        self.command = command
        self.previousIndex = previousIndex
        self.expectedIndex = expectedIndex
    }
}

struct ProductSpaceTransitionRequest: Equatable, Sendable {
    let beforeIndexes: [String: Int]
    let steps: [ProductSpaceTransitionStep]
    let finalExpectedIndexes: [String: Int]

    init(
        beforeIndexes: [String: Int],
        steps: [ProductSpaceTransitionStep],
        finalExpectedIndexes: [String: Int]
    ) {
        self.beforeIndexes = beforeIndexes
        self.steps = steps
        self.finalExpectedIndexes = finalExpectedIndexes
    }
}

enum ProductRelativeTransitionRequestFailure: Equatable, Sendable {
    case unavailableTargetDisplay
}

enum ProductRelativeTransitionRequest: Equatable, Sendable {
    case request(ProductSpaceTransitionRequest)
    case boundary
    case failure(ProductRelativeTransitionRequestFailure)
}

enum ProductCaptureTransitionDirective: Equatable, Sendable {
    case continueCapture
    case waitForInFlight
    case restore
}

struct ProductCaptureTransitionProgress: Equatable, Sendable {
    private(set) var confirmedSteps: [ProductSpaceTransitionStep] = []
    private(set) var isOperationInFlight = false
    private(set) var isStopPending = false

    mutating func beginOperation() -> Bool {
        guard !isOperationInFlight, !isStopPending else {
            return false
        }
        isOperationInFlight = true
        return true
    }

    mutating func requestStop() -> ProductCaptureTransitionDirective {
        isStopPending = true
        return isOperationInFlight ? .waitForInFlight : .restore
    }

    mutating func finishOperation(
        confirmedStep: ProductSpaceTransitionStep?
    ) -> ProductCaptureTransitionDirective {
        guard isOperationInFlight else {
            return isStopPending ? .restore : .continueCapture
        }
        if let confirmedStep {
            confirmedSteps.append(confirmedStep)
        }
        isOperationInFlight = false
        return isStopPending ? .restore : .continueCapture
    }
}

struct ProductCaptureCommitSelection: Equatable, Sendable {
    let currentContextID: String
    let needsSync: Bool
}

enum ProductCaptureCommitSelector {
    static func selection(
        contexts: [ContextDefinition],
        restoredIndexes: [String: Int],
        fallbackContextID: String
    ) -> ProductCaptureCommitSelection {
        let matches = contexts.filter { context in
            !context.displayIDs.isEmpty
                && context.displayIDs.allSatisfy { displayID in
                    restoredIndexes[displayID] == context.spaceIndex(for: displayID)
                }
        }
        if matches.count == 1, let match = matches.first {
            return ProductCaptureCommitSelection(
                currentContextID: match.id,
                needsSync: false
            )
        }

        let fallback = contexts.contains(where: { $0.id == fallbackContextID })
            ? fallbackContextID
            : contexts.first?.id ?? fallbackContextID
        return ProductCaptureCommitSelection(
            currentContextID: fallback,
            needsSync: true
        )
    }
}

enum ProductSpaceTransitionRequestBuilder {
    static func stationary(
        displays: [InstantCaptureDisplay]
    ) -> ProductSpaceTransitionRequest {
        let indexes = Dictionary(
            uniqueKeysWithValues: displays.map { ($0.displayID, $0.currentSpaceIndex) }
        )
        return complete(beforeIndexes: indexes, steps: [])
    }

    static func relative(
        displays: [InstantCaptureDisplay],
        targetDisplayIDs: Set<String>,
        command: SwitchCommand
    ) -> ProductRelativeTransitionRequest {
        let displaysByID = Dictionary(
            uniqueKeysWithValues: displays.map { ($0.displayID, $0) }
        )
        guard targetDisplayIDs.allSatisfy({ displaysByID[$0] != nil }) else {
            return .failure(.unavailableTargetDisplay)
        }

        let steps = displays
            .filter { targetDisplayIDs.contains($0.displayID) }
            .compactMap { display -> ProductSpaceTransitionStep? in
                let expectedIndex: Int
                switch command {
                case .previous:
                    guard display.currentSpaceIndex > 0 else {
                        return nil
                    }
                    expectedIndex = display.currentSpaceIndex - 1
                case .next:
                    guard display.currentSpaceIndex + 1 < display.spaceCount else {
                        return nil
                    }
                    expectedIndex = display.currentSpaceIndex + 1
                }
                return ProductSpaceTransitionStep(
                    displayID: display.displayID,
                    command: command,
                    previousIndex: display.currentSpaceIndex,
                    expectedIndex: expectedIndex
                )
            }

        guard !steps.isEmpty else {
            return .boundary
        }

        return .request(complete(
            beforeIndexes: stationary(displays: displays).beforeIndexes,
            steps: steps
        ))
    }

    static func captureRestore(
        initialIndexes: [String: Int],
        successfulSteps: [ProductSpaceTransitionStep]
    ) -> ProductSpaceTransitionRequest? {
        var currentIndexes = initialIndexes
        for step in successfulSteps {
            guard currentIndexes[step.displayID] == step.previousIndex else {
                return nil
            }
            currentIndexes[step.displayID] = step.expectedIndex
        }

        let reverseSteps = successfulSteps.reversed().map { step in
            ProductSpaceTransitionStep(
                displayID: step.displayID,
                command: step.command == .next ? .previous : .next,
                previousIndex: step.expectedIndex,
                expectedIndex: step.previousIndex
            )
        }
        return ProductSpaceTransitionRequest(
            beforeIndexes: currentIndexes,
            steps: reverseSteps,
            finalExpectedIndexes: initialIndexes
        )
    }

    static func complete(
        beforeIndexes: [String: Int],
        steps: [ProductSpaceTransitionStep]
    ) -> ProductSpaceTransitionRequest {
        let finalExpectedIndexes = steps.reduce(into: beforeIndexes) { indexes, step in
            indexes[step.displayID] = step.expectedIndex
        }
        return ProductSpaceTransitionRequest(
            beforeIndexes: beforeIndexes,
            steps: steps,
            finalExpectedIndexes: finalExpectedIndexes
        )
    }
}

enum ProductSpaceTransitionFailure: Equatable, Sendable {
    case invalidStep(displayID: String, expectedPreviousIndex: Int, actualPreviousIndex: Int?)
    case postRejected(displayID: String, command: SwitchCommand)
    case verification(SpaceLayoutVerificationFailure)
}

struct ProductSpaceTransitionFailureProgress: Equatable, Sendable {
    let confirmedIndexes: [String: Int]
    let mayHaveMoved: Bool
}

enum ProductSpaceTransitionResult: Equatable, Sendable {
    case success([String: Int])
    case failure(
        ProductSpaceTransitionFailure,
        progress: ProductSpaceTransitionFailureProgress
    )

    var mayHaveMoved: Bool {
        guard case .failure(_, let progress) = self else {
            return false
        }
        return progress.mayHaveMoved
    }
}

/// Executes each product Space transition as a verified Dock swipe.
/// Blocking — callers must run it away from the main actor.
struct ProductSpaceTransitionRunner: Sendable {
    let makeExecutor: @Sendable (String) -> any SpaceCommandExecuting
    let verifier: StableSpaceLayoutVerifier

    func run(_ request: ProductSpaceTransitionRequest) -> ProductSpaceTransitionResult {
        var currentIndexes = request.beforeIndexes
        var didAttemptPost = false

        func failed(_ failure: ProductSpaceTransitionFailure) -> ProductSpaceTransitionResult {
            .failure(
                failure,
                progress: ProductSpaceTransitionFailureProgress(
                    confirmedIndexes: currentIndexes,
                    mayHaveMoved: didAttemptPost
                )
            )
        }

        for step in request.steps {
            guard currentIndexes[step.displayID] == step.previousIndex else {
                return failed(.invalidStep(
                    displayID: step.displayID,
                    expectedPreviousIndex: step.previousIndex,
                    actualPreviousIndex: currentIndexes[step.displayID]
                ))
            }

            didAttemptPost = true
            guard makeExecutor(step.displayID).execute(step.command) else {
                return failed(.postRejected(displayID: step.displayID, command: step.command))
            }

            var expectedIndexes = currentIndexes
            expectedIndexes[step.displayID] = step.expectedIndex
            switch verifier.waitForExpected(
                previous: currentIndexes,
                expected: expectedIndexes,
                changedDisplayIDs: [step.displayID]
            ) {
            case .success(let indexes):
                currentIndexes = indexes
            case .failure(let failure):
                return failed(.verification(failure))
            }
        }

        switch verifier.waitForExpectedThenStable(
            previous: currentIndexes,
            expected: request.finalExpectedIndexes,
            changedDisplayIDs: Set(
                request.finalExpectedIndexes.compactMap { displayID, index in
                    currentIndexes[displayID] == index ? nil : displayID
                }
            )
        ) {
        case .success(let indexes):
            return .success(indexes)
        case .failure(let failure):
            return failed(.verification(failure))
        }
    }
}
