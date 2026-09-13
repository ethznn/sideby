import SidebyCore

/// Refreshes selected displays from the observed layout. Labels and mappings
/// for other displays survive, but obsolete selected-display rows do not.
enum WorkspaceCaptureRefreshPolicy {
    static func contexts(
        discovered: [ContextDefinition],
        existing: [ContextDefinition],
        selectedDisplayIDs: Set<String>
    ) -> [ContextDefinition] {
        var result = discovered.map { candidate in
            guard let previous = existing.first(where: { $0.order == candidate.order }) else {
                return candidate
            }
            var mappings = previous.displaySpaceIndexes.filter { !selectedDisplayIDs.contains($0.key) }
            mappings.merge(candidate.displaySpaceIndexes) { _, new in new }
            return ContextDefinition(
                id: previous.id, order: candidate.order, name: previous.name,
                displaySpaceIndexes: mappings
            )
        }
        let discoveredOrders = Set(discovered.map(\.order))
        result += existing.compactMap { previous in
            guard !discoveredOrders.contains(previous.order) else { return nil }
            let retained = previous.displaySpaceIndexes.filter { !selectedDisplayIDs.contains($0.key) }
            guard !retained.isEmpty else { return nil }
            return ContextDefinition(id: previous.id, order: previous.order, name: previous.name,
                                     displaySpaceIndexes: retained)
        }
        return result.sorted { $0.order < $1.order }
    }
}
