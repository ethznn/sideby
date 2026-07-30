import SidebyCore

enum ProductContextActivationLayoutPolicy {
    static func isAdmitted(
        _ captureDisplays: [InstantCaptureDisplay]?,
        selectedDisplayIDs: Set<String>,
        requiresCompleteSelectedLayout: Bool
    ) -> Bool {
        guard let captureDisplays, !captureDisplays.isEmpty else {
            return false
        }
        guard requiresCompleteSelectedLayout else {
            return true
        }

        return ProductInstantContextCaptureStartPolicy.plan(
            for: captureDisplays,
            selectedDisplayIDs: selectedDisplayIDs
        ) != nil
    }
}
