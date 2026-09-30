import Foundation

/// Durable workspace identity and edit history live in the same settings write as the plan.
/// A missing desktop stays remembered; a later desktop at the same index is never its replacement.
public struct SavedWorkspaceLibrary: Codable, Equatable, Sendable {
    public var initialized = false
    public var bookmarks: [String: [String: String]] = [:]
    public var shortcutSlots: [String: Int] = [:]
    public var lastIncludedDisplayIDs: [String]?
    public var undo: SavedWorkspaceUndo?

    public init() {}

    public mutating func assignAvailableShortcut(to id: String) {
        guard shortcutSlots[id] == nil,
              let slot = (1...10).first(where: { !shortcutSlots.values.contains($0) }) else { return }
        shortcutSlots[id] = slot
    }

    public func resolved(_ contexts: [ContextDefinition], spaceKeys: [String: [String]]) -> [ContextDefinition] {
        contexts.map { context in
            var indexes = context.displaySpaceIndexes
            for (displayID, key) in bookmarks[context.id] ?? [:] {
                guard let keys = spaceKeys[displayID], Set(keys).count == keys.count,
                      let index = keys.firstIndex(of: key) else { continue }
                indexes[displayID] = index
            }
            return ContextDefinition(id: context.id, order: context.order, name: context.name,
                                     displaySpaceIndexes: indexes)
        }
    }

    public func unavailableMembers(of context: ContextDefinition, connectedIDs: Set<String>,
                                   spaceKeys: [String: [String]]) -> Set<String> {
        Set(context.displayIDs.filter { id in
            guard connectedIDs.contains(id) else { return false }
            guard let key = bookmarks[context.id]?[id], let keys = spaceKeys[id],
                  Set(keys).count == keys.count, let index = context.spaceIndex(for: id),
                  keys.indices.contains(index) else { return true }
            return keys[index] != key
        })
    }
}

public struct SavedWorkspaceUndo: Codable, Equatable, Sendable {
    public let contexts: [ContextDefinition]
    public let bookmarks: [String: [String: String]]
    public let shortcutSlots: [String: Int]
    public let label: String
    public let resultingContexts: [ContextDefinition]
    public let resultingBookmarks: [String: [String: String]]

    public init(contexts: [ContextDefinition], bookmarks: [String: [String: String]],
                shortcutSlots: [String: Int], label: String, resultingContexts: [ContextDefinition],
                resultingBookmarks: [String: [String: String]]) {
        self.contexts = contexts
        self.bookmarks = bookmarks
        self.shortcutSlots = shortcutSlots
        self.label = label
        self.resultingContexts = resultingContexts
        self.resultingBookmarks = resultingBookmarks
    }
}
