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
}
