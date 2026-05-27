public struct KeyboardShortcut: Equatable, Codable, Hashable, Sendable {
    public let keyCode: UInt16
    public let modifiers: ModifierFlags

    public init(keyCode: UInt16, modifiers: ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

public typealias SBSKeyboardShortcut = KeyboardShortcut

public enum KeyboardShortcutRole: String, CaseIterable, Codable, Sendable {
    case previous
    case next
}

public enum KeyboardShortcutValidationIssue: Equatable, Hashable, Sendable {
    case missingPrimaryModifier(role: KeyboardShortcutRole)
    case duplicatePreviousAndNext
    case reservedSystemShortcut(role: KeyboardShortcutRole)
    case emptyGestureModifier
}

public enum KeyboardShortcutValidator {
    public static func issues(
        previous: KeyboardShortcut,
        next: KeyboardShortcut,
        gestureModifiers: ModifierFlags
    ) -> [KeyboardShortcutValidationIssue] {
        var issues = issues(for: previous, role: .previous)
        issues.append(contentsOf: self.issues(for: next, role: .next))

        if previous == next {
            issues.append(.duplicatePreviousAndNext)
        }

        if !isValidGestureModifierSet(gestureModifiers) {
            issues.append(.emptyGestureModifier)
        }

        return issues
    }

    public static func issues(
        for shortcut: KeyboardShortcut,
        role: KeyboardShortcutRole
    ) -> [KeyboardShortcutValidationIssue] {
        var issues: [KeyboardShortcutValidationIssue] = []

        if shortcut.modifiers.intersection(.primaryShortcutModifiers).isEmpty {
            issues.append(.missingPrimaryModifier(role: role))
        }

        if isReservedSystemShortcut(shortcut) {
            issues.append(.reservedSystemShortcut(role: role))
        }

        return issues
    }

    public static func isValidGestureModifierSet(_ modifiers: ModifierFlags) -> Bool {
        !modifiers.intersection(.configurableGestureModifiers).isEmpty
    }

    public static func isReservedSystemShortcut(_ shortcut: KeyboardShortcut) -> Bool {
        reservedSystemShortcuts.contains(shortcut)
    }

    private static let reservedSystemShortcuts: Set<KeyboardShortcut> = [
        KeyboardShortcut(keyCode: 48, modifiers: [.command]),
        KeyboardShortcut(keyCode: 49, modifiers: [.command]),
        KeyboardShortcut(keyCode: 123, modifiers: [.control]),
        KeyboardShortcut(keyCode: 124, modifiers: [.control]),
        KeyboardShortcut(keyCode: 125, modifiers: [.control]),
        KeyboardShortcut(keyCode: 126, modifiers: [.control])
    ]
}
