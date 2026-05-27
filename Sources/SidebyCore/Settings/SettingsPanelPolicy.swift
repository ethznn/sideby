public enum SettingsPanelVariant: Equatable, Sendable {
    case product
    case dev
}

public enum SettingsPanelSection: String, CaseIterable, Identifiable, Equatable, Sendable {
    case overview
    case displays
    case input
    case permissions
    case general
    case advanced

    public var id: Self { self }
}

public enum SettingsPanelPolicy: Sendable {
    public static func sections(for variant: SettingsPanelVariant) -> [SettingsPanelSection] {
        switch variant {
        case .product:
            return [.overview, .displays, .input, .permissions, .general]
        case .dev:
            return SettingsPanelSection.allCases
        }
    }

    public static func showsLastInputStatus(for variant: SettingsPanelVariant) -> Bool {
        switch variant {
        case .product:
            return false
        case .dev:
            return true
        }
    }
}
