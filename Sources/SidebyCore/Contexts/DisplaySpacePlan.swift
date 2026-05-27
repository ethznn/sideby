public struct DisplaySpaceSlot: Equatable, Codable, Identifiable, Sendable {
    public let order: Int
    public var label: String

    public init(order: Int, label: String = "") {
        self.order = max(order, 1)
        self.label = label
    }

    public var id: Int {
        order
    }
}

public struct DisplaySpaceSet: Equatable, Codable, Identifiable, Sendable {
    public let displayID: String
    public var spaces: [DisplaySpaceSlot]

    public init(displayID: String, spaces: [DisplaySpaceSlot] = [DisplaySpaceSlot(order: 1)]) {
        self.displayID = displayID
        self.spaces = spaces.sorted { $0.order < $1.order }
        ensureFirstSpace()
    }

    public var id: String {
        displayID
    }

    public func label(spaceOrder: Int) -> String? {
        spaces.first { $0.order == spaceOrder }?.label
    }

    public mutating func updateLabel(spaceOrder: Int, label: String) {
        let normalizedOrder = max(spaceOrder, 1)
        ensureSpaces(upTo: normalizedOrder)
        guard let index = spaces.firstIndex(where: { $0.order == normalizedOrder }) else {
            return
        }

        spaces[index].label = label
    }

    public mutating func ensureSpaces(upTo count: Int) {
        let targetCount = max(count, 1)
        let existingOrders = Set(spaces.map(\.order))
        for order in 1...targetCount where !existingOrders.contains(order) {
            spaces.append(DisplaySpaceSlot(order: order))
        }
        spaces.sort { $0.order < $1.order }
    }

    private mutating func ensureFirstSpace() {
        if spaces.isEmpty {
            spaces = [DisplaySpaceSlot(order: 1)]
        }
        spaces.sort { $0.order < $1.order }
    }
}

public struct DisplaySpacePlan: Equatable, Codable, Sendable {
    public var displaySpaces: [DisplaySpaceSet]
    public var defaultCaptureCount: Int

    public init(displaySpaces: [DisplaySpaceSet] = [], defaultCaptureCount: Int = 4) {
        self.displaySpaces = displaySpaces.sorted { $0.displayID < $1.displayID }
        self.defaultCaptureCount = max(defaultCaptureCount, 1)
    }

    public static let `default` = DisplaySpacePlan()

    public mutating func reconcile(with displayLayout: DisplayLayout) {
        for display in displayLayout.displays where !displaySpaces.contains(where: { $0.displayID == display.id }) {
            displaySpaces.append(DisplaySpaceSet(displayID: display.id))
        }

        displaySpaces.sort { lhs, rhs in
            let lhsIndex = displayLayout.displays.firstIndex { $0.id == lhs.displayID } ?? Int.max
            let rhsIndex = displayLayout.displays.firstIndex { $0.id == rhs.displayID } ?? Int.max
            if lhsIndex == rhsIndex {
                return lhs.displayID < rhs.displayID
            }
            return lhsIndex < rhsIndex
        }
    }

    public func spaces(displayID: String) -> [DisplaySpaceSlot] {
        displaySpaces
            .first { $0.displayID == displayID }?
            .spaces ?? [DisplaySpaceSlot(order: 1)]
    }

    public func label(displayID: String, spaceOrder: Int) -> String? {
        displaySpaces
            .first { $0.displayID == displayID }?
            .label(spaceOrder: spaceOrder)
    }

    public mutating func updateLabel(displayID: String, spaceOrder: Int, label: String) {
        let normalizedOrder = max(spaceOrder, 1)
        if !displaySpaces.contains(where: { $0.displayID == displayID }) {
            displaySpaces.append(DisplaySpaceSet(displayID: displayID))
        }

        guard let index = displaySpaces.firstIndex(where: { $0.displayID == displayID }) else {
            return
        }

        displaySpaces[index].updateLabel(spaceOrder: normalizedOrder, label: label)
    }

    public mutating func ensureSpaces(displayID: String, upTo count: Int) {
        if !displaySpaces.contains(where: { $0.displayID == displayID }) {
            displaySpaces.append(DisplaySpaceSet(displayID: displayID))
        }
        guard let index = displaySpaces.firstIndex(where: { $0.displayID == displayID }) else {
            return
        }
        displaySpaces[index].ensureSpaces(upTo: count)
    }

    public func visibleSpaceCount(
        displayID: String,
        captureCount: Int,
        suggestionOrders: Set<Int>
    ) -> Int {
        let labeledMax = spaces(displayID: displayID).map(\.order).max() ?? 1
        let suggestedMax = suggestionOrders.max() ?? 1
        return max(1, captureCount, labeledMax, suggestedMax)
    }
}
