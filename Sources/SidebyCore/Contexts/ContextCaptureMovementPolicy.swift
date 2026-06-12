import Foundation

public struct ContextCaptureDisplayMovementObservation: Equatable, Sendable {
    public let displayID: String
    public let didObserveActiveSpaceChange: Bool
    public let visibleFingerprintBefore: String?
    public let visibleFingerprintAfter: String?

    public init(
        displayID: String,
        didObserveActiveSpaceChange: Bool,
        visibleFingerprintBefore: String?,
        visibleFingerprintAfter: String?
    ) {
        self.displayID = displayID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.didObserveActiveSpaceChange = didObserveActiveSpaceChange
        self.visibleFingerprintBefore = Self.normalizedFingerprint(visibleFingerprintBefore)
        self.visibleFingerprintAfter = Self.normalizedFingerprint(visibleFingerprintAfter)
    }

    public var didChangeVisibleFingerprint: Bool {
        visibleFingerprintBefore != visibleFingerprintAfter
    }

    public var didMove: Bool {
        didObserveActiveSpaceChange || didChangeVisibleFingerprint
    }

    private static func normalizedFingerprint(_ fingerprint: String?) -> String? {
        guard let fingerprint else {
            return nil
        }

        let trimmed = fingerprint.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public enum ContextCaptureMovementPolicy: Sendable {
    public static func movedDisplayIDs(
        from observations: [ContextCaptureDisplayMovementObservation]
    ) -> Set<String> {
        Set(
            observations
                .filter(\.didMove)
                .map(\.displayID)
                .filter { !$0.isEmpty }
        )
    }

    public static func didObserveAnyMovement(
        didObserveActiveSpaceChange: Bool,
        observations: [ContextCaptureDisplayMovementObservation]
    ) -> Bool {
        didObserveActiveSpaceChange || observations.contains(where: \.didMove)
    }

    private static let maxConsecutiveNoMoves = 2

    public static func forwardDecision(
        activeDisplayIDs: Set<String>,
        movedDisplayIDs: Set<String>,
        noMoveStreaks: [String: Int]
    ) -> ContextCaptureForwardDecision {
        var updatedStreaks: [String: Int] = [:]
        var retainedDisplayIDs = Set<String>()
        var confirmedDisplayIDs = Set<String>()

        for displayID in activeDisplayIDs {
            if movedDisplayIDs.contains(displayID) {
                updatedStreaks[displayID] = 0
                retainedDisplayIDs.insert(displayID)
                confirmedDisplayIDs.insert(displayID)
            } else {
                let streak = (noMoveStreaks[displayID] ?? 0) + 1
                updatedStreaks[displayID] = streak
                if streak < Self.maxConsecutiveNoMoves {
                    retainedDisplayIDs.insert(displayID)
                }
            }
        }

        return ContextCaptureForwardDecision(
            activeDisplayIDs: retainedDisplayIDs,
            confirmedDisplayIDs: confirmedDisplayIDs,
            noMoveStreaks: updatedStreaks
        )
    }
}

public struct ContextCaptureForwardDecision: Equatable, Sendable {
    /// Displays that should keep receiving forward presses (confirmed movers
    /// plus displays still within their no-move grace window).
    public let activeDisplayIDs: Set<String>
    /// Displays whose arrival at the new order was actually observed. Only
    /// these may become members of the next recorded context.
    public let confirmedDisplayIDs: Set<String>
    public let noMoveStreaks: [String: Int]

    public init(
        activeDisplayIDs: Set<String>,
        confirmedDisplayIDs: Set<String>,
        noMoveStreaks: [String: Int]
    ) {
        self.activeDisplayIDs = activeDisplayIDs
        self.confirmedDisplayIDs = confirmedDisplayIDs
        self.noMoveStreaks = noMoveStreaks
    }
}
