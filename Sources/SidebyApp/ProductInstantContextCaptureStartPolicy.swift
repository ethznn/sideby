import SidebyCore

enum ProductInstantContextCaptureStartPolicy {
    static func plan(
        for captureDisplays: [InstantCaptureDisplay]?,
        selectedDisplayIDs: Set<String>
    ) -> InstantCapturePlan? {
        guard let captureDisplays,
              !captureDisplays.isEmpty,
              Set(captureDisplays.map(\.displayID)) == selectedDisplayIDs
        else {
            return nil
        }

        return InstantContextCapturePlanner.plan(for: captureDisplays)
    }
}
