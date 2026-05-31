public enum ExternalSpaceChangeContextPolicy: Sendable {
    public static func shouldPauseContextMatching(
        isSidebyEnabled: Bool,
        plan: ContextPlan
    ) -> Bool {
        isSidebyEnabled
            && plan.isPinned
            && plan.syncState == .synchronized
    }
}
