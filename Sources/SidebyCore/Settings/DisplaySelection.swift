/// Durable display choices, including displays that are temporarily disconnected.
public struct DisplaySelection: Equatable, Codable, Sendable {
    public private(set) var hasInitialized: Bool
    public private(set) var selectedDisplayIDs: Set<String>
    public private(set) var knownDisplayNames: [String: String]

    public init(
        hasInitialized: Bool = false,
        selectedDisplayIDs: Set<String> = [],
        knownDisplayNames: [String: String] = [:]
    ) {
        self.hasInitialized = hasInitialized
        self.selectedDisplayIDs = selectedDisplayIDs
        self.knownDisplayNames = knownDisplayNames
    }

    /// Only the first observed nonempty layout is selected automatically.
    /// Later discoveries update names without changing any remembered choices.
    public mutating func reconcile(with layout: DisplayLayout) {
        for display in layout.displays {
            knownDisplayNames[display.id] = display.name
        }
        guard !hasInitialized, !layout.displays.isEmpty else { return }
        hasInitialized = true
        selectedDisplayIDs.formUnion(layout.displays.map(\.id))
    }

    public func connectedSelectedDisplayIDs(in layout: DisplayLayout) -> Set<String> {
        selectedDisplayIDs.intersection(layout.displays.map(\.id))
    }

    public mutating func setSelected(_ isSelected: Bool, displayID: String, name: String? = nil) {
        hasInitialized = true
        if let name {
            knownDisplayNames[displayID] = name
        }
        if isSelected {
            selectedDisplayIDs.insert(displayID)
        } else {
            selectedDisplayIDs.remove(displayID)
        }
    }

    public mutating func selectAllConnected(in layout: DisplayLayout) {
        reconcile(with: layout)
        selectedDisplayIDs.formUnion(layout.displays.map(\.id))
    }
}
