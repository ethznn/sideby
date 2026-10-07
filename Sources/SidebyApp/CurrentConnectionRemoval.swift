import SidebyCore

enum ConnectionRemovalScope: Equatable {
    case all
    case display(String)
    case connections(Set<String>)
}

struct ConnectionRemovalProposal: Equatable {
    let scope: ConnectionRemovalScope
    let snapshot: WorkspaceDeleteAllProposal
    let count: Int
}

extension SidebyAppModel {
    func prepareConnectionRemoval(_ scope: ConnectionRemovalScope) -> ConnectionRemovalProposal? {
        guard let snapshot = prepareDeleteAllSavedWorkspaces() else { return nil }
        let count: Int
        switch scope {
        case .all: count = snapshot.contexts.count
        case .display(let id): count = snapshot.contexts.filter { $0.displayIDs.contains(id) }.count
        case .connections(let ids):
            guard ids.isSubset(of: Set(snapshot.contexts.map(\.id))) else { return nil }
            count = ids.count
        }
        guard count > 0 else { return nil }
        return .init(scope: scope, snapshot: snapshot, count: count)
    }

    /// Remove only confirmed connections, including offline members, in one
    /// checked settings write. No Space, window or display participation changes.
    @discardableResult
    func removeConnections(_ proposal: ConnectionRemovalProposal) -> Bool {
        guard canChangeSavedWorkspaces else { return false }
        guard settings.contextPlan.contexts == proposal.snapshot.contexts,
              settings.savedWorkspaces.bookmarks == proposal.snapshot.bookmarks else {
            showWorkspaceFeedback(connectionCopy.removalChanged, kind: .failure)
            return false
        }
        if proposal.scope == .all {
            return deleteAllSavedWorkspaces(proposal.snapshot, label: connectionCopy.clearedAll(proposal.count))
        }
        var next = settings
        let contexts = next.contextPlan.contexts.compactMap { context -> ContextDefinition? in
            switch proposal.scope {
            case .all: return nil
            case .connections(let ids): return ids.contains(context.id) ? nil : context
            case .display(let displayID):
                guard context.displayIDs.contains(displayID) else { return context }
                var members = context.displaySpaceIndexes
                members.removeValue(forKey: displayID)
                next.savedWorkspaces.bookmarks[context.id]?.removeValue(forKey: displayID)
                guard !members.isEmpty else { return nil }
                return .init(id: context.id, order: context.order, name: context.name, displaySpaceIndexes: members)
            }
        }
        let remaining = Set(contexts.map(\.id))
        for id in Set(next.contextPlan.contexts.map(\.id)).subtracting(remaining) {
            next.savedWorkspaces.bookmarks.removeValue(forKey: id)
            next.savedWorkspaces.shortcutSlots.removeValue(forKey: id)
        }
        next.contextPlan.replaceContexts(contexts, currentContextID: next.contextPlan.currentContextID)
        let label: String
        if case .display(let displayID) = proposal.scope {
            label = connectionCopy.text("Cleared \(proposal.count) connections for \(displayName(for: displayID)). You can undo this.",
                "\(displayName(for: displayID))의 연결 \(proposal.count)개를 비웠어요. 되돌릴 수 있습니다.")
        } else {
            label = connectionCopy.text("Removed \(proposal.count) selected connections. You can undo this.",
                "선택한 연결 \(proposal.count)개를 삭제했어요. 되돌릴 수 있습니다.")
        }
        return commitSavedWorkspaceChange(next, label: label)
    }
}

extension CurrentConnectionStrings {
    var selectConnections: String { text("Select connections", "여러 연결 선택") }
    var selectAll: String { text("Select all", "전체 선택") }
    var finishSelection: String { text("Cancel", "선택 취소") }
    var selectionHint: String { text("Click a heading or cell to select its whole column. Spaces will not move.", "열 제목이나 칸을 누르면 해당 열이 선택됩니다. 실제 Space는 이동하지 않습니다.") }
    var removeSelectedAction: String { text("Remove connections", "선택한 연결 삭제") }
    func removeSelected(_ count: Int) -> String { text("Remove \(count) selected…", "선택한 \(count)개 삭제…") }
    func selectedState(_ selected: Bool) -> String { selected ? text("Selected", "선택됨") : text("Not selected", "선택 안 됨") }
    var removalChanged: String { text("Connections changed. Review them and try again.", "연결이 변경됐어요. 확인한 뒤 다시 시도해 주세요.") }
    func removalTitle(_ proposal: ConnectionRemovalProposal, displayName: String) -> String {
        switch proposal.scope {
        case .all: return clearAllTitle(proposal.count)
        case .display: return text("Clear \(proposal.count) connections for \(displayName)?", "\(displayName)의 연결 \(proposal.count)개를 비울까요?")
        case .connections: return text("Remove \(proposal.count) selected connections?", "선택한 연결 \(proposal.count)개를 삭제할까요?")
        }
    }
    func removalMessage(_ scope: ConnectionRemovalScope) -> String {
        switch scope {
        case .all: return clearAllMessage
        case .display:
            return text("Connections on other displays stay as they are. Columns with no connections left are removed. Your Spaces and open apps stay as they are.",
                "다른 모니터의 연결은 유지합니다. 연결이 하나도 남지 않는 열은 사라집니다. 실제 Space와 열린 앱은 그대로입니다.") + " " + undoHistoryHint
        case .connections:
            return text("Only selected columns are removed, including their connections on disconnected displays. Other connections, Spaces and open apps stay as they are. Undo restores the selected connections together.",
                "선택한 열의 연결만 삭제하며 연결 해제된 모니터도 포함합니다. 다른 연결과 실제 Space, 열린 앱은 그대로입니다. 되돌리기 한 번으로 함께 복구할 수 있습니다.")
        }
    }
}
