public enum SettingsPanelVariant: Equatable, Sendable {
    case product
    case dev
}

public enum SettingsPanelSection: String, CaseIterable, Identifiable, Equatable, Sendable {
    case overview
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
            return [.overview, .input, .permissions, .general]
        case .dev:
            return [.overview, .input, .permissions, .general, .advanced]
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
