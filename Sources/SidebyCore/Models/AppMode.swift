public enum AppMode: String, Codable, Equatable, Sendable {
    case together
    case shortcut
    case swipe
    case separateDisplays = "separate-displays"
    case focus

    public var id: String {
        switch self {
        case .together:
            "together"
        case .shortcut:
            "shortcut"
        case .swipe:
            "swipe"
        case .separateDisplays:
            "separate-displays"
        case .focus:
            "focus"
        }
    }
}
