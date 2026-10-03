import AppKit

@MainActor
final class ProductApplicationDelegate: NSObject, NSApplicationDelegate {
    var hasUnsavedChanges: () -> Bool = { false }
    var resolveUnsavedChanges: () -> Bool = { false }
    var activateApplication: () -> Void = { NSApplication.shared.activate(ignoringOtherApps: true) }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard hasUnsavedChanges() else { return .terminateNow }
        activateApplication()
        return resolveUnsavedChanges() ? .terminateNow : .terminateCancel
    }
}
