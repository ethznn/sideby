import SidebyCore

public enum ContextRowState: Equatable, Sendable {
    case current
    case needsSync
    case normal
}

public struct ContextListRow: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let order: Int
    public let state: ContextRowState

    public init(id: String, name: String, order: Int, state: ContextRowState) {
        self.id = id
        self.name = name
        self.order = order
        self.state = state
    }
}

public enum ContextListModel {
    public static func rows(plan: ContextPlan) -> [ContextListRow] {
        plan.contexts.sorted { $0.order < $1.order }.map { context in
            let state: ContextRowState
            if plan.currentContextID == context.id {
                state = plan.syncState == .needsSync ? .needsSync : .current
            } else {
                state = .normal
            }

            return ContextListRow(
                id: context.id,
                name: context.name,
                order: context.order,
                state: state
            )
        }
    }
}
