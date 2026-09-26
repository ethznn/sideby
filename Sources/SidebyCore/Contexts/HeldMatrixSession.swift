public struct HeldMatrixConfiguration: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var shortcut: KeyboardShortcut
    public init(isEnabled: Bool = true, shortcut: KeyboardShortcut = .init(keyCode: 49, modifiers: [.option, .shift])) {
        self.isEnabled = isEnabled
        self.shortcut = shortcut
    }

    public static func isValid(_ shortcut: KeyboardShortcut) -> Bool {
        let modifierKeys: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
        return shortcut.keyCode < 127 && shortcut.keyCode != 53 && !modifierKeys.contains(shortcut.keyCode)
            && !shortcut.modifiers.intersection(.primaryShortcutModifiers).isEmpty
            && shortcut.modifiers.isSubset(of: .configurableGestureModifiers)
            && !KeyboardShortcutValidator.isReservedSystemShortcut(shortcut)
            && !ContextKeyboardShortcutCatalog.bindings.contains { $0.shortcut == shortcut }
    }
}

/// A press owns only the panel. An accepted click's transition can outlive it.
public struct HeldMatrixSession: Equatable, Sendable {
    public private(set) var generation = 0
    public private(set) var isHeld = false
    public private(set) var isVisible = false
    public private(set) var isTransitioning = false

    public init() {}

    @discardableResult public mutating func press() -> Int? {
        guard !isHeld else { return nil }
        generation += 1
        isHeld = true
        isVisible = true
        return generation
    }

    public mutating func release() { isHeld = false; isVisible = false }
    public mutating func dismiss() { isVisible = false }

    public mutating func beginTransition(session: Int) -> Bool {
        guard session == generation, isHeld, isVisible, !isTransitioning else { return false }
        isTransitioning = true
        return true
    }

    public mutating func finishTransition() { isTransitioning = false }
}
