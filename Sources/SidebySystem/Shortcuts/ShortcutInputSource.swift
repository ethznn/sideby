import SidebyCore

public struct KeyboardEvent: Equatable, Sendable {
    public let keyCode: UInt16
    public let modifiers: ModifierFlags

    public init(keyCode: UInt16, modifiers: ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

public struct ShortcutInputSource: Sendable {
    let previousShortcut: KeyboardShortcut
    let nextShortcut: KeyboardShortcut

    public init(previousShortcut: KeyboardShortcut, nextShortcut: KeyboardShortcut) {
        self.previousShortcut = previousShortcut
        self.nextShortcut = nextShortcut
    }

    public func command(for event: KeyboardEvent) -> SwitchCommand? {
        if matches(event, shortcut: previousShortcut) {
            return .previous
        }

        if matches(event, shortcut: nextShortcut) {
            return .next
        }

        return nil
    }

    private func matches(_ event: KeyboardEvent, shortcut: KeyboardShortcut) -> Bool {
        event.keyCode == shortcut.keyCode && event.modifiers == shortcut.modifiers
    }
}
