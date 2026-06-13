public enum ContextCurrentMatcher {
    /// Returns the context whose connected member displays all sit at the
    /// context's Space index (order - 1). Displays that are not members of a
    /// context never constrain it; a context with no connected member cannot
    /// match. Membership is monotonic across orders, so at most one context
    /// matches.
    public static func currentContextID(
        contexts: [ContextDefinition],
        displayIndexes: [String: Int]
    ) -> String? {
        for context in contexts {
            let connectedMembers = context.displayIDs.filter { displayIndexes[$0] != nil }
            guard !connectedMembers.isEmpty else {
                continue
            }
            let expectedIndex = context.order - 1
            if connectedMembers.allSatisfy({ displayIndexes[$0] == expectedIndex }) {
                return context.id
            }
        }
        return nil
    }
}
