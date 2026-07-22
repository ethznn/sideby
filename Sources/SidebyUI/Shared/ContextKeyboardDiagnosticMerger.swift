import SidebyCore

public enum ContextKeyboardDiagnosticMerger {
    public static func diagnostics(
        runtimeDiagnostics: [DiagnosticState],
        failedCommands: [ContextKeyboardCommand],
        strings: SBSStrings
    ) -> [DiagnosticState] {
        mergingRegistrationFailures(
            failedCommands,
            into: runtimeDiagnostics,
            strings: strings
        )
    }

    public static func mergingRegistrationFailures(
        _ failedCommands: [ContextKeyboardCommand],
        into diagnostics: [DiagnosticState],
        strings: SBSStrings
    ) -> [DiagnosticState] {
        guard !failedCommands.isEmpty else {
            return diagnostics
        }

        let shortcuts = failedCommands.compactMap { command in
            ContextKeyboardShortcutCatalog.binding(for: command)
        }
        .map { KeyboardShortcutFormatter.shortcutText($0.shortcut) }
        .joined(separator: ", ")
        let warning = DiagnosticState(
            severity: .warning,
            title: strings.contextKeyboardRegistrationTitle,
            message: strings.contextKeyboardRegistrationMessage(shortcuts: shortcuts),
            actionLabel: nil
        )

        guard !diagnostics.contains(warning) else {
            return diagnostics
        }
        return diagnostics + [warning]
    }
}
