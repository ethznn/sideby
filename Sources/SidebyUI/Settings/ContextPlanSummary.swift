import SidebyCore

public enum ContextPlanSummary {
    public static func summary(
        for context: ContextDefinition,
        displays: [DisplayInfo],
        strings: SBSStrings
    ) -> String {
        let labels = displays
            .compactMap { display in
                context.label(for: display.id)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }

        let detail = labels.isEmpty
            ? strings.displayCountChip(displays.count)
            : labels.joined(separator: " / ")

        return "\(context.name) · \(detail)"
    }
}
