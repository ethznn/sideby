import AppKit

public final class DismissibleFloatingPanel: NSPanel {
    public var onDismissShortcut: (() -> Void)?

    public override var canBecomeKey: Bool {
        true
    }

    public override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
    }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let commandW = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .contains(.command)
            && event.charactersIgnoringModifiers?.lowercased() == "w"

        if commandW {
            onDismissShortcut?()
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    public override func cancelOperation(_ sender: Any?) {
        onDismissShortcut?()
    }

    public override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onDismissShortcut?()
            return
        }

        super.keyDown(with: event)
    }
}
