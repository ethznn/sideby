public struct NamedContext: Equatable, Codable, Sendable {
    public let index: Int
    public var name: String

    public init(index: Int, name: String) {
        self.index = index
        self.name = name
    }
}

public struct ContextList: Equatable, Codable, Sendable {
    public var contexts: [NamedContext]

    public init(contexts: [NamedContext] = []) {
        self.contexts = contexts
    }

    public func name(for index: Int) -> String? {
        contexts.first { $0.index == index }?.name
    }

    public mutating func setName(_ name: String, for index: Int) {
        if let existingIndex = contexts.firstIndex(where: { $0.index == index }) {
            contexts[existingIndex].name = name
        } else {
            contexts.append(NamedContext(index: index, name: name))
        }
    }
}
