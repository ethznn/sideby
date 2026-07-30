import Foundation

public struct ContextCaptureAlignmentCandidate: Equatable, Identifiable, Sendable {
    public let id: String
    public let order: Int
    public let name: String

    public init(id: String, order: Int, name: String) {
        self.id = id
        self.order = order
        self.name = name
    }
}

public enum ContextCaptureAlignmentPolicy {
    public static func candidates(
        contexts: [ContextDefinition],
        selectedDisplayIDs: Set<String>
    ) -> [ContextCaptureAlignmentCandidate] {
        guard !selectedDisplayIDs.isEmpty else { return [] }

        return contexts
            .compactMap { context in
                let members = Set(context.displayIDs)
                guard selectedDisplayIDs.isSubset(of: members) else { return nil }
                return ContextCaptureAlignmentCandidate(
                    id: context.id,
                    order: context.order,
                    name: context.name
                )
            }
            .sorted { $0.order < $1.order }
    }
}
