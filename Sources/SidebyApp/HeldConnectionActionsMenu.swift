import AppKit
import SwiftUI

/// Pin the held panel before native menu tracking, so releasing the opening
/// shortcut cannot close the panel while choosing an action or reaching Undo.
struct HeldConnectionActionsMenu: NSViewRepresentable {
    let label: String
    let removeTitle: String
    let identifier: String
    let enabled: Bool
    let willOpen: () -> Void
    let remove: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        button.isBordered = false
        button.bezelStyle = .inline
        button.imagePosition = .imageOnly
        (button.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = context.coordinator
        let title = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        title.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
        menu.addItem(title)
        let deletion = NSMenuItem(title: removeTitle, action: #selector(Coordinator.removeConnection(_:)), keyEquivalent: "")
        deletion.target = context.coordinator
        deletion.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        menu.addItem(deletion)
        button.menu = menu
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.willOpen = willOpen
        context.coordinator.remove = remove
        button.isEnabled = enabled
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.setAccessibilityIdentifier(identifier)
        button.menu?.items.last?.title = removeTitle
        button.menu?.items.last?.isEnabled = enabled
    }

    @MainActor final class Coordinator: NSObject, NSMenuDelegate {
        var willOpen: (() -> Void)?
        var remove: (() -> Void)?

        func menuWillOpen(_ menu: NSMenu) { willOpen?() }

        @objc func removeConnection(_ sender: NSMenuItem) {
            guard sender.isEnabled else { return }
            remove?()
        }
    }
}
