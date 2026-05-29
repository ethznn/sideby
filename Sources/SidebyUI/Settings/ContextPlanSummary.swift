import SidebyCore

public enum ContextPlanSummary {
    public static func summary(
        for context: ContextDefinition,
        displays: [DisplayInfo],
        strings: SBSStrings
    ) -> String {
        _ = displays
        _ = strings
        return context.name
    }
}
