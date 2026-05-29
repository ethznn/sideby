import Foundation

public enum ContextPlanMigration {
    public static func migrate(from legacyPlan: DisplaySpacePlan) -> ContextPlan {
        let displaySets = legacyPlan.displaySpaces.sorted { lhs, rhs in
            lhs.displayID < rhs.displayID
        }
        let maxOrder = displaySets.flatMap { $0.spaces.map(\.order) }.max() ?? 1

        let contexts = (1...maxOrder).map { order in
            ContextDefinition(
                id: "context-\(order)",
                order: order,
                name: migratedName(order: order, displaySets: displaySets)
            )
        }

        return ContextPlan(
            contexts: contexts,
            currentContextID: contexts.first?.id ?? "context-1",
            syncState: .synchronized,
            captureLimit: legacyPlan.defaultCaptureCount
        )
    }

    private static func migratedName(order: Int, displaySets: [DisplaySpaceSet]) -> String {
        var seen = Set<String>()
        var labels: [String] = []

        for displaySet in displaySets {
            guard let rawLabel = displaySet.label(spaceOrder: order) else {
                continue
            }
            let label = rawLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty, !seen.contains(label) else {
                continue
            }
            seen.insert(label)
            labels.append(label)
        }

        return labels.isEmpty ? "Context \(order)" : labels.joined(separator: " / ")
    }
}
