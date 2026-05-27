public struct AdvancedModeSettings: Equatable, Codable, Sendable {
    public var isSeparateDisplaysEnabled: Bool
    public var exposesExperimentalControls: Bool

    public init(isSeparateDisplaysEnabled: Bool, exposesExperimentalControls: Bool) {
        self.isSeparateDisplaysEnabled = isSeparateDisplaysEnabled
        self.exposesExperimentalControls = exposesExperimentalControls
    }

    public static let `default` = AdvancedModeSettings(
        isSeparateDisplaysEnabled: false,
        exposesExperimentalControls: false
    )
}

public struct AdvancedModePolicy: Sendable {
    public init() {}

    public func diagnostic(for settings: AdvancedModeSettings) -> DiagnosticState? {
        guard settings.isSeparateDisplaysEnabled else {
            return nil
        }

        return DiagnosticState(
            severity: .warning,
            title: "Advanced mode is experimental",
            message: "Separate display Spaces may not stay perfectly synchronized on every macOS setup.",
            actionLabel: nil
        )
    }
}
