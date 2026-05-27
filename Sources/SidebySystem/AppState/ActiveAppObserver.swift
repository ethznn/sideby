import AppKit
import SidebyCore

public struct MacActiveAppObserver: ActiveAppObserving {
    public init() {}

    public func currentApp() -> ActiveAppInfo? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleIdentifier = app.bundleIdentifier else {
            return nil
        }

        return ActiveAppInfo(
            bundleIdentifier: bundleIdentifier,
            localizedName: app.localizedName
        )
    }
}
