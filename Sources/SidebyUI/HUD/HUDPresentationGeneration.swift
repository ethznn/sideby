public struct HUDPresentationGeneration: Equatable, Sendable {
    private var value = 0

    public init() {}

    public mutating func advance() -> Int {
        value += 1
        return value
    }

    public func isCurrent(_ generation: Int) -> Bool {
        value == generation
    }
}
