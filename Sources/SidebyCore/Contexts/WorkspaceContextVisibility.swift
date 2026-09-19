import Foundation

/// Shared by the matrix, menu shortcuts and relative workspace navigation.
public enum WorkspaceContextVisibility {
    public static func contexts(in plan: ContextPlan, connectedDisplayIDs: Set<String>) -> [ContextDefinition] {
        plan.contexts.sorted { $0.order < $1.order }.filter {
            $0.displayIDs.isEmpty || !Set($0.displayIDs).isDisjoint(with: connectedDisplayIDs)
        }
    }

    public static func plan(_ plan: ContextPlan, connectedDisplayIDs: Set<String>) -> ContextPlan {
        ContextPlan(contexts: contexts(in: plan, connectedDisplayIDs: connectedDisplayIDs),
                    currentContextID: plan.currentContextID, syncState: plan.syncState, isPinned: plan.isPinned)
    }
}
