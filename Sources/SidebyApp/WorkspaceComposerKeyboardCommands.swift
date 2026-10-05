import AppKit
import SwiftUI

/// The library lives in an AppKit-hosted window, outside the MenuBarExtra scene.
/// Keep its commands in that window and leave text editing and sheets alone.
struct WorkspaceComposerKeyboardCommands: NSViewRepresentable {
    let model: SidebyAppModel

    func makeNSView(context: Context) -> CommandView {
        let view = CommandView()
        view.model = model
        return view
    }

    func updateNSView(_ view: CommandView, context: Context) { view.model = model }

    final class CommandView: NSView {
        weak var model: SidebyAppModel?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard let window, window.isKeyWindow, window.attachedSheet == nil, NSApp.modalWindow == nil,
                  event.type == .keyDown,
                  event.modifierFlags.intersection([.command, .option, .control, .shift]) == [.command],
                  let model else { return false }
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "s":
                guard model.canCommitWorkspaceComposer else { return false }
                _ = model.commitWorkspaceComposer()
                return true
            case "z":
                guard !(window.firstResponder is NSTextView), model.canUndoWorkspaceComposer else { return false }
                model.undoWorkspaceComposer()
                return true
            default:
                return false
            }
        }
    }
}
