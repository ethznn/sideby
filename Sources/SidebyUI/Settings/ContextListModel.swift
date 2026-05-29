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
    public let displayIDs: [String]

    public init(
        id: String,
        name: String,
        order: Int,
        state: ContextRowState,
        displayIDs: [String] = []
    ) {
        self.id = id
        self.name = name
        self.order = order
        self.state = state
        self.displayIDs = displayIDs
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
                state: state,
                displayIDs: context.displayIDs
            )
        }
    }
}

public struct ContextMatrixColumn: Equatable, Identifiable, Sendable {
    public let id: String
    public let order: Int
    public let name: String
    public let state: ContextRowState

    public init(id: String, order: Int, name: String, state: ContextRowState) {
        self.id = id
        self.order = order
        self.name = name
        self.state = state
    }
}

public struct ContextMatrixCell: Equatable, Identifiable, Sendable {
    public let id: String
    public let contextID: String
    public let displayID: String
    public let isIncluded: Bool

    public init(contextID: String, displayID: String, isIncluded: Bool) {
        self.id = "\(displayID)-\(contextID)"
        self.contextID = contextID
        self.displayID = displayID
        self.isIncluded = isIncluded
    }
}

public struct ContextMatrixRow: Equatable, Identifiable, Sendable {
    public let id: String
    public let displayID: String
    public let displayName: String
    public let cells: [ContextMatrixCell]

    public init(displayID: String, displayName: String, cells: [ContextMatrixCell]) {
        self.id = displayID
        self.displayID = displayID
        self.displayName = displayName
        self.cells = cells
    }
}

public struct ContextMatrix: Equatable, Sendable {
    public let columns: [ContextMatrixColumn]
    public let rows: [ContextMatrixRow]

    public init(columns: [ContextMatrixColumn], rows: [ContextMatrixRow]) {
        self.columns = columns
        self.rows = rows
    }
}

public enum ContextMatrixModel {
    public static func matrix(plan: ContextPlan, displays: [DisplayInfo]) -> ContextMatrix {
        let contexts = plan.contexts.sorted { $0.order < $1.order }
        let columns = contexts.map { context in
            let state: ContextRowState
            if plan.currentContextID == context.id {
                state = plan.syncState == .needsSync ? .needsSync : .current
            } else {
                state = .normal
            }

            return ContextMatrixColumn(
                id: context.id,
                order: context.order,
                name: context.name,
                state: state
            )
        }
        let rows = displays.map { display in
            ContextMatrixRow(
                displayID: display.id,
                displayName: display.name,
                cells: contexts.map { context in
                    ContextMatrixCell(
                        contextID: context.id,
                        displayID: display.id,
                        isIncluded: context.displayIDs.contains(display.id)
                    )
                }
            )
        }

        return ContextMatrix(columns: columns, rows: rows)
    }
}
