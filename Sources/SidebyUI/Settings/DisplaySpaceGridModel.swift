import SidebyCore

public struct DisplaySpaceGridCell: Equatable, Identifiable, Sendable {
    public let displayID: String
    public let spaceOrder: Int
    public let label: String
    public let suggestion: VisibleAppSuggestion?

    public init(
        displayID: String,
        spaceOrder: Int,
        label: String,
        suggestion: VisibleAppSuggestion?
    ) {
        self.displayID = displayID
        self.spaceOrder = spaceOrder
        self.label = label
        self.suggestion = suggestion
    }

    public var id: String {
        "\(displayID)-\(spaceOrder)"
    }
}

public struct DisplaySpaceGridRow: Equatable, Identifiable, Sendable {
    public let displayID: String
    public let displayName: String
    public let isPrimary: Bool
    public let isBuiltin: Bool
    public let cells: [DisplaySpaceGridCell]

    public init(
        displayID: String,
        displayName: String,
        isPrimary: Bool,
        isBuiltin: Bool,
        cells: [DisplaySpaceGridCell]
    ) {
        self.displayID = displayID
        self.displayName = displayName
        self.isPrimary = isPrimary
        self.isBuiltin = isBuiltin
        self.cells = cells
    }

    public var id: String {
        displayID
    }
}

public enum DisplaySpaceGridModel {
    public static func rows(
        displays: [DisplayInfo],
        plan: DisplaySpacePlan,
        captureCount: Int,
        suggestionsByDisplayID: [String: [Int: VisibleAppSuggestion]]
    ) -> [DisplaySpaceGridRow] {
        let orders = spaceOrders(
            displays: displays,
            plan: plan,
            captureCount: captureCount,
            suggestionsByDisplayID: suggestionsByDisplayID
        )

        return displays.map { display in
            DisplaySpaceGridRow(
                displayID: display.id,
                displayName: display.name,
                isPrimary: display.isPrimary,
                isBuiltin: display.isBuiltin,
                cells: orders.map { order in
                    DisplaySpaceGridCell(
                        displayID: display.id,
                        spaceOrder: order,
                        label: plan.label(displayID: display.id, spaceOrder: order) ?? "",
                        suggestion: suggestionsByDisplayID[display.id]?[order]
                    )
                }
            )
        }
    }

    public static func spaceOrders(
        displays: [DisplayInfo],
        plan: DisplaySpacePlan,
        captureCount: Int,
        suggestionsByDisplayID: [String: [Int: VisibleAppSuggestion]]
    ) -> [Int] {
        let maxSpaceCount = displays
            .map { display in
                let suggestionOrders = suggestionsByDisplayID[display.id]
                    .map { Set($0.keys) } ?? []
                return plan.visibleSpaceCount(
                    displayID: display.id,
                    captureCount: captureCount,
                    suggestionOrders: suggestionOrders
                )
            }
            .max() ?? max(1, captureCount)

        return Array(1...max(maxSpaceCount, 1))
    }
}
