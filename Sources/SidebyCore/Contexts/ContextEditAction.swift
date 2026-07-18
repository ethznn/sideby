public enum ContextEditAction {
    public static func minimumContextCount(
        selectedDisplayIDs: Set<String>,
        readLiveDisplays: () -> [InstantCaptureDisplay]?
    ) -> Int? {
        guard let displays = readLiveDisplays() else {
            return nil
        }
        return ContextEditPolicy.minimumContextCount(
            selectedDisplayIDs: selectedDisplayIDs,
            displays: displays
        )
    }

    @discardableResult
    public static func deleteContext(
        id: String,
        from plan: inout ContextPlan,
        isEditingAllowed: Bool,
        selectedDisplayIDs: Set<String>,
        readLiveDisplays: () -> [InstantCaptureDisplay]?
    ) -> Bool {
        guard isEditingAllowed,
              let minimumContextCount = minimumContextCount(
                  selectedDisplayIDs: selectedDisplayIDs,
                  readLiveDisplays: readLiveDisplays
              )
        else {
            return false
        }
        return plan.deleteContext(id: id, minimumContextCount: minimumContextCount)
    }

    public static func requiresDeleteConfirmation(
        contextID: String,
        contexts: [ContextDefinition]
    ) -> Bool {
        guard let context = contexts.first(where: { $0.id == contextID }) else {
            return false
        }
        return ContextEditPolicy.requiresDeleteConfirmation(for: context)
    }
}
