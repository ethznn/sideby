import SidebyCore

public enum ContextRowState: Equatable, Sendable {
    case current
    case needsSync
    case paused
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
            return ContextListRow(
                id: context.id,
                name: context.name,
                order: context.order,
                state: rowState(for: context, plan: plan),
                displayIDs: context.displayIDs
            )
        }
    }

    private static func rowState(for context: ContextDefinition, plan: ContextPlan) -> ContextRowState {
        guard plan.currentContextID == context.id else {
            return .normal
        }

        guard plan.syncState == .needsSync else {
            return .current
        }

        return plan.isPinned ? .needsSync : .paused
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
    public let spaceIndex: Int?

    public init(contextID: String, displayID: String, isIncluded: Bool, spaceIndex: Int? = nil) {
        self.id = "\(displayID)-\(contextID)"
        self.contextID = contextID
        self.displayID = displayID
        self.isIncluded = isIncluded
        self.spaceIndex = isIncluded ? spaceIndex : nil
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
    public static func matrix(
        plan: ContextPlan,
        displays: [DisplayInfo],
        displayRowOrder: [String] = []
    ) -> ContextMatrix {
        let contexts = plan.contexts.sorted { $0.order < $1.order }
        let columns = contexts.map { context in
            return ContextMatrixColumn(
                id: context.id,
                order: context.order,
                name: context.name,
                state: columnState(for: context, plan: plan)
            )
        }
        let rows = orderedDisplays(displays, displayRowOrder: displayRowOrder).map { display in
            ContextMatrixRow(
                displayID: display.id,
                displayName: display.name,
                cells: contexts.map { context in
                    let spaceIndex = context.spaceIndex(for: display.id)
                    return ContextMatrixCell(
                        contextID: context.id,
                        displayID: display.id,
                        isIncluded: spaceIndex != nil,
                        spaceIndex: spaceIndex
                    )
                }
            )
        }

        return ContextMatrix(columns: columns, rows: rows)
    }

    public static func displayRowOrder(
        moving displayID: String,
        to targetDisplayID: String,
        visibleDisplayIDs: [String],
        currentOrder: [String]
    ) -> [String] {
        var visibleOrder = orderedDisplayIDs(
            visibleDisplayIDs: visibleDisplayIDs,
            displayRowOrder: currentOrder
        )
        guard let sourceIndex = visibleOrder.firstIndex(of: displayID),
              let targetIndex = visibleOrder.firstIndex(of: targetDisplayID),
              sourceIndex != targetIndex
        else {
            return normalizedDisplayRowOrder(
                visibleDisplayIDs: visibleDisplayIDs,
                currentOrder: currentOrder
            )
        }

        let moved = visibleOrder.remove(at: sourceIndex)
        visibleOrder.insert(moved, at: targetIndex)

        let visibleSet = Set(visibleDisplayIDs)
        let hiddenOrder = currentOrder.filter { !visibleSet.contains($0) }
        return visibleOrder + hiddenOrder
    }

    private static func orderedDisplays(
        _ displays: [DisplayInfo],
        displayRowOrder: [String]
    ) -> [DisplayInfo] {
        let displaysByID = Dictionary(uniqueKeysWithValues: displays.map { ($0.id, $0) })
        return orderedDisplayIDs(
            visibleDisplayIDs: displays.map(\.id),
            displayRowOrder: displayRowOrder
        ).compactMap { displaysByID[$0] }
    }

    private static func normalizedDisplayRowOrder(
        visibleDisplayIDs: [String],
        currentOrder: [String]
    ) -> [String] {
        orderedDisplayIDs(
            visibleDisplayIDs: visibleDisplayIDs,
            displayRowOrder: currentOrder
        ) + currentOrder.filter { !Set(visibleDisplayIDs).contains($0) }
    }

    private static func orderedDisplayIDs(
        visibleDisplayIDs: [String],
        displayRowOrder: [String]
    ) -> [String] {
        var seen = Set<String>()
        let visibleSet = Set(visibleDisplayIDs)
        let saved = displayRowOrder
            .filter { visibleSet.contains($0) }
            .filter { seen.insert($0).inserted }
        let appended = visibleDisplayIDs.filter { seen.insert($0).inserted }
        return saved + appended
    }

    private static func columnState(for context: ContextDefinition, plan: ContextPlan) -> ContextRowState {
        guard plan.currentContextID == context.id else {
            return .normal
        }

        guard plan.syncState == .needsSync else {
            return .current
        }

        return plan.isPinned ? .needsSync : .paused
    }
}
