import SidebyCore

public struct WorkspaceChooserRow: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let connectedDisplayCount: Int
    public let totalDisplayCount: Int
    public let movingDisplayCount: Int
    public let isCurrent: Bool
    public let shortcut: String?
    public var hasMoveTargets: Bool { movingDisplayCount > 0 }
}

public enum WorkspaceChooserModel {
    public static func rows(
        plan: ContextPlan,
        connectedDisplayIDs: Set<String>,
        selectedDisplayIDs: Set<String>,
        verifiedCurrentContextID: String?,
        failedCommands: [ContextKeyboardCommand] = []
    ) -> [WorkspaceChooserRow] {
        plan.contexts.sorted { $0.order < $1.order }.enumerated().compactMap { index, context in
            guard !context.displayIDs.isEmpty else { return nil }
            let position = index + 1
            let members = Set(context.displayIDs)
            let connected = members.intersection(connectedDisplayIDs)
            guard !connected.isEmpty else { return nil }
            let hasShortcut = ContextKeyboardShortcutCatalog.binding(for: .activate(position: position)) != nil
                && !failedCommands.contains(.activate(position: position))
            return WorkspaceChooserRow(
                id: context.id,
                name: context.name,
                connectedDisplayCount: connected.count,
                totalDisplayCount: members.count,
                movingDisplayCount: connected.intersection(selectedDisplayIDs).count,
                isCurrent: context.id == verifiedCurrentContextID,
                shortcut: hasShortcut ? "⌥⇧\(position == 10 ? 0 : position)" : nil
            )
        }
    }
}
