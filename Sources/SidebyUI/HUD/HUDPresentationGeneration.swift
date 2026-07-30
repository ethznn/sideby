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

    @discardableResult
    public mutating func consumeCurrent(_ generation: Int) -> Bool {
        guard value == generation else {
            return false
        }
        value += 1
        return true
    }
}
