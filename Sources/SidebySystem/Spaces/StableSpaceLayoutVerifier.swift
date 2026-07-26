import Foundation

public enum SpaceLayoutVerificationFailure: Equatable, Sendable {
    case unreadableLayout
    case timeout
    case wrongDirection
    case unexpectedDisplayChange(displayID: String)
    case unstableTransition
}

public enum SpaceLayoutVerificationResult: Equatable, Sendable {
    case success([String: Int])
    case failure(SpaceLayoutVerificationFailure)
}

public struct StableSpaceLayoutVerifierDependencies: Sendable {
    public let now: @Sendable () -> TimeInterval
    public let sleep: @Sendable (TimeInterval) -> Void
    public let readIndexes: @Sendable () -> [String: Int]?

    public init(
        now: @escaping @Sendable () -> TimeInterval,
        sleep: @escaping @Sendable (TimeInterval) -> Void,
        readIndexes: @escaping @Sendable () -> [String: Int]?
    ) {
        self.now = now
        self.sleep = sleep
        self.readIndexes = readIndexes
    }
}

/// Waits for every display to reach the intended layout, then confirms that
/// the whole layout stays there for the requested stability window.
/// Blocking — call off the main thread.
public struct StableSpaceLayoutVerifier: Sendable {
    public static let livePollInterval: TimeInterval = 0.025
    public static let liveStabilityDuration: TimeInterval = 0.75
    public static let liveMaximumPollsPerPhase = 40

    private let pollInterval: TimeInterval
    private let stabilityDuration: TimeInterval
    private let maximumPolls: Int
    private let dependencies: StableSpaceLayoutVerifierDependencies

    public init(
        pollInterval: TimeInterval = Self.livePollInterval,
        stabilityDuration: TimeInterval = Self.liveStabilityDuration,
        maximumPolls: Int = Self.liveMaximumPollsPerPhase,
        dependencies: StableSpaceLayoutVerifierDependencies
    ) {
        self.pollInterval = max(pollInterval, 0.001)
        self.stabilityDuration = max(stabilityDuration, 0)
        self.maximumPolls = max(maximumPolls, 1)
        self.dependencies = dependencies
    }

    public static func live(
        readIndexes: @escaping @Sendable () -> [String: Int]?
    ) -> StableSpaceLayoutVerifier {
        StableSpaceLayoutVerifier(
            dependencies: StableSpaceLayoutVerifierDependencies(
                now: { ProcessInfo.processInfo.systemUptime },
                sleep: { Thread.sleep(forTimeInterval: $0) },
                readIndexes: readIndexes
            )
        )
    }

    public func waitForExpectedThenStable(
        previous: [String: Int],
        expected: [String: Int],
        changedDisplayIDs: Set<String>
    ) -> SpaceLayoutVerificationResult {
        switch waitForExpected(
            previous: previous,
            expected: expected,
            changedDisplayIDs: changedDisplayIDs
        ) {
        case .success:
            return waitForStableExpectedLayout(expected)
        case .failure(let failure):
            return .failure(failure)
        }
    }

    /// Waits only for the exact expected layout. Adjacent steps use this
    /// acknowledgement; stability is reserved for the completed request.
    public func waitForExpected(
        previous: [String: Int],
        expected: [String: Int],
        changedDisplayIDs: Set<String>
    ) -> SpaceLayoutVerificationResult {
        for poll in 0..<maximumPolls {
            guard let indexes = dependencies.readIndexes() else {
                return .failure(.unreadableLayout)
            }

            if indexes == expected {
                return .success(indexes)
            }

            if let failure = initialFailure(
                indexes: indexes,
                previous: previous,
                expected: expected,
                changedDisplayIDs: changedDisplayIDs
            ) {
                return .failure(failure)
            }

            if poll + 1 < maximumPolls {
                dependencies.sleep(pollInterval)
            }
        }

        return .failure(.timeout)
    }

    private func waitForStableExpectedLayout(
        _ expected: [String: Int]
    ) -> SpaceLayoutVerificationResult {
        let stableSince = dependencies.now()

        for poll in 0..<maximumPolls {
            guard let indexes = dependencies.readIndexes() else {
                return .failure(.unreadableLayout)
            }
            guard indexes == expected else {
                return .failure(.unstableTransition)
            }

            if dependencies.now() - stableSince >= stabilityDuration {
                return .success(indexes)
            }

            if poll + 1 < maximumPolls {
                dependencies.sleep(pollInterval)
            }
        }

        return .failure(.timeout)
    }

    private func initialFailure(
        indexes: [String: Int],
        previous: [String: Int],
        expected: [String: Int],
        changedDisplayIDs: Set<String>
    ) -> SpaceLayoutVerificationFailure? {
        for displayID in expected.keys.sorted() {
            guard let index = indexes[displayID],
                  let previousIndex = previous[displayID],
                  let expectedIndex = expected[displayID] else {
                return .unreadableLayout
            }

            if changedDisplayIDs.contains(displayID) {
                if index != previousIndex && index != expectedIndex {
                    return .wrongDirection
                }
            } else if index != previousIndex {
                return .unexpectedDisplayChange(displayID: displayID)
            }
        }

        return nil
    }
}
