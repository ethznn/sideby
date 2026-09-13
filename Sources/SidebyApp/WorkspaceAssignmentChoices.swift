import SidebyCore

struct WorkspaceAssignmentChoice: Equatable, Identifiable {
    var id: Int { spaceIndex }
    let sourceContextID: String
    let spaceIndex: Int
    let name: String
}

enum WorkspaceAssignmentChoices {
    static func options(plan: ContextPlan, displayID: String, observedSpaceCount: Int?) -> [WorkspaceAssignmentChoice] {
        guard let count = observedSpaceCount, count > 0 else { return [] }
        return (0..<count).map { index in
            let contexts = plan.contexts.sorted { $0.order < $1.order }.filter { $0.spaceIndex(for: displayID) == index }
            return WorkspaceAssignmentChoice(sourceContextID: contexts.first?.id ?? "", spaceIndex: index,
                                             name: contexts.map(\.name).joined(separator: ", "))
        }
    }
}
