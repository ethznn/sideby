import AppKit

public enum MenuBarOnlyApplicationPresentation {
    public static let activationPolicy: NSApplication.ActivationPolicy = .accessory

    @MainActor
    @discardableResult
    public static func apply(to application: NSApplication = .shared) -> Bool {
        application.setActivationPolicy(activationPolicy)
    }
}
