public enum SwipeDirection: Codable, Equatable, Sendable {
    case left
    case right
}

public enum SwitchCommand: Codable, Equatable, Sendable {
    case previous
    case next

    public var direction: SwipeDirection {
        switch self {
        case .previous:
            .left
        case .next:
            .right
        }
    }
}
