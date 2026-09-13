struct WorkspaceSettingsSelection: Equatable {
    private(set) var selectedContextID: String?
    private(set) var missingContextID: String?

    init(selectedContextID: String? = nil) {
        self.selectedContextID = selectedContextID
    }

    mutating func reconcile(contextIDs: [String], preferredID: String?) {
        if let missingContextID, contextIDs.contains(missingContextID) {
            self.missingContextID = nil
        }
        if let preferredID {
            missingContextID = contextIDs.contains(preferredID) ? nil : preferredID
            selectedContextID = missingContextID == nil ? preferredID : contextIDs.first
        } else if let selectedContextID, !contextIDs.contains(selectedContextID) {
            missingContextID = selectedContextID
            self.selectedContextID = contextIDs.first
        } else if selectedContextID == nil {
            selectedContextID = contextIDs.first
        }
    }
}
