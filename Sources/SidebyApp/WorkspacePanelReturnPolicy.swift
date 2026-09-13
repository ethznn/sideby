enum WorkspacePanelReturnPolicy {
    static func shouldReturnToWork(succeeded: Bool, isEditing: Bool, isGuiding: Bool) -> Bool {
        succeeded && !isEditing && !isGuiding
    }
}
