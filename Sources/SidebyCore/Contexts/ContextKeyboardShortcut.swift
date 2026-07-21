public enum ContextKeyboardCommand: Equatable, Sendable {
    case activate(position: Int)
    case move(SwitchCommand)
}

public struct ContextKeyboardShortcutBinding: Equatable, Sendable {
    public let shortcut: KeyboardShortcut
    public let command: ContextKeyboardCommand

    public init(shortcut: KeyboardShortcut, command: ContextKeyboardCommand) {
        self.shortcut = shortcut
        self.command = command
    }
}

public enum ContextKeyboardShortcutCatalog: Sendable {
    public static let bindings: [ContextKeyboardShortcutBinding] = [
        number(position: 1, keyCode: 18),
        number(position: 2, keyCode: 19),
        number(position: 3, keyCode: 20),
        number(position: 4, keyCode: 21),
        number(position: 5, keyCode: 23),
        number(position: 6, keyCode: 22),
        number(position: 7, keyCode: 26),
        number(position: 8, keyCode: 28),
        number(position: 9, keyCode: 25),
        number(position: 10, keyCode: 29),
        binding(keyCode: 123, command: .move(.previous)),
        binding(keyCode: 124, command: .move(.next))
    ]

    public static func binding(
        for command: ContextKeyboardCommand
    ) -> ContextKeyboardShortcutBinding? {
        bindings.first { $0.command == command }
    }

    private static func number(
        position: Int,
        keyCode: UInt16
    ) -> ContextKeyboardShortcutBinding {
        binding(keyCode: keyCode, command: .activate(position: position))
    }

    private static func binding(
        keyCode: UInt16,
        command: ContextKeyboardCommand
    ) -> ContextKeyboardShortcutBinding {
        ContextKeyboardShortcutBinding(
            shortcut: KeyboardShortcut(keyCode: keyCode, modifiers: [.option, .shift]),
            command: command
        )
    }
}

public enum ContextKeyboardAction: Equatable, Sendable {
    case ignore
    case showSidebyOff
    case showMissingContext(position: Int)
    case activate(contextID: String)
    case move(SwitchCommand)
}

public enum ContextKeyboardShortcutPolicy: Sendable {
    public static func action(
        command: ContextKeyboardCommand,
        contextPlan: ContextPlan,
        isSidebyEnabled: Bool,
        isSwitching: Bool,
        isCapturing: Bool
    ) -> ContextKeyboardAction {
        guard !isSwitching, !isCapturing else {
            return .ignore
        }
        guard isSidebyEnabled else {
            return .showSidebyOff
        }

        switch command {
        case .move(let switchCommand):
            return .move(switchCommand)
        case .activate(let position):
            guard (1...10).contains(position) else {
                return .ignore
            }
            let contexts = contextPlan.contexts.sorted { $0.order < $1.order }
            let index = position - 1
            guard contexts.indices.contains(index) else {
                return .showMissingContext(position: position)
            }
            return .activate(contextID: contexts[index].id)
        }
    }
}
