public enum ExternalSpaceChangeContextPolicy: Sendable {
    public static func shouldPauseContextMatching(
        isSidebyEnabled: Bool,
        plan: ContextPlan
    ) -> Bool {
        isSidebyEnabled
            && plan.isPinned
            && plan.syncState == .synchronized
    }

    /// Live tracking runs even when the plan needs sync (so it can
    /// self-heal), unlike pausing which only fires from a synchronized state.
    public static func shouldTrackCurrentContext(
        isSidebyEnabled: Bool,
        plan: ContextPlan
    ) -> Bool {
        isSidebyEnabled
            && plan.isPinned
            && !plan.contexts.isEmpty
    }
}
