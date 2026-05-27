public struct FocusModeSettings: Equatable, Codable, Sendable {
    public var isEnabled: Bool
    public var lockedCommands: [SwitchCommand]

    public init(isEnabled: Bool, lockedCommands: [SwitchCommand]) {
        self.isEnabled = isEnabled
        self.lockedCommands = lockedCommands
    }

    public static let disabled = FocusModeSettings(isEnabled: false, lockedCommands: [])
}

public struct FocusModePolicy: Sendable {
    private let settings: FocusModeSettings

    public init(settings: FocusModeSettings) {
        self.settings = settings
    }

    public func allows(_ command: SwitchCommand) -> Bool {
        guard settings.isEnabled else {
            return true
        }

        return !settings.lockedCommands.contains(command)
    }

    public func diagnostic(for command: SwitchCommand) -> DiagnosticState? {
        guard !allows(command) else {
            return nil
        }

        return DiagnosticState(
            severity: .warning,
            title: "Meeting Locked",
            message: "This direction is locked while Focus Mode is on.",
            actionLabel: "Turn Off Focus"
        )
    }
}
