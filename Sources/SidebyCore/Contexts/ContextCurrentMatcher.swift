public enum ContextCurrentMatcher {
    /// Returns the context whose connected member displays all sit at the
    /// context's mapped Space index. Displays that are not members of a
    /// context never constrain it; a context with no connected member cannot
    /// match.
    public static func currentContextID(
        contexts: [ContextDefinition],
        displayIndexes: [String: Int]
    ) -> String? {
        for context in contexts {
            let connectedMembers = context.displayIDs.filter { displayIndexes[$0] != nil }
            guard !connectedMembers.isEmpty else {
                continue
            }
            if connectedMembers.allSatisfy({ displayIndexes[$0] == context.spaceIndex(for: $0) }) {
                return context.id
            }
        }
        return nil
    }
}
