import Foundation
import SidebyCore

enum WorkspaceSaveFeedbackKind { case notice, success, failure }

/// One live connection table. Each edit changes only bookmarks, never Spaces or app windows.
extension SidebyAppModel {
    var connectionCopy: CurrentConnectionStrings { .init(language: settings.language) }

    func showWorkspaceFeedback(_ message: String, kind: WorkspaceSaveFeedbackKind) {
        workspaceSaveMessage = message
        workspaceSaveFeedbackKind = kind
    }

    /// Read current contents even when an old connection points to a missing
    /// Space. This is presentation data; it must never rename or repair a link.
    func refreshCurrentDesktopContents() {
        guard !isSwitching, contextCaptureSession == nil, pendingContextCaptureAlignment == nil,
              let provider = workspaceNameSuggestionProvider,
              let observation = workspaceObservation(includingUnselectedDisplays: true) else { return }
        let names = provider.names(for: displayLayout, spaceIDsByDisplayID: observation.spaceIDsByDisplayID)
        guard workspaceObservation(includingUnselectedDisplays: true)?.spaceIDsByDisplayID == observation.spaceIDsByDisplayID else { return }
        workspaceDesktopNames = names
        workspaceDesktopNameSpaceIDs = observation.spaceIDsByDisplayID
    }

    @discardableResult
    func connectCurrentDesktopOrder() -> Bool {
        guard canChangeSavedWorkspaces, settings.contextPlan.contexts.isEmpty,
              let observation = workspaceObservation(includingUnselectedDisplays: true) else { return false }
        let ids = connectedWorkspaceDisplayIDs.filter { selectedDisplayIDs.contains($0) }
        let keys = ids.compactMap { composerKeys($0, observation: observation) }
        guard !ids.isEmpty, keys.count == ids.count, let count = keys.map(\.count).max(), count > 0 else {
            showWorkspaceFeedback(saveCopy.readUnavailable, kind: .failure); return false
        }
        var next = settings
        var contexts: [ContextDefinition] = []
        for index in 0..<count {
            let id = "connection-" + UUID().uuidString
            var members: [String: Int] = [:]
            for (display, values) in zip(ids, keys) where values.indices.contains(index) {
                members[display] = index
                next.savedWorkspaces.bookmarks[id, default: [:]][display] = values[index]
            }
            contexts.append(.init(id: id, order: index + 1, name: connectionCopy.connection(index + 1), displaySpaceIndexes: members))
            next.savedWorkspaces.assignAvailableShortcut(to: id)
        }
        next.savedWorkspaces.initialized = true
        next.contextPlan.replaceContexts(contexts, currentContextID: "")
        return commitSavedWorkspaceChange(next, label: connectionCopy.applied)
    }

    /// Resolve the chosen durable key again at the moment of the edit. A reordered
    /// Space remains the same choice; a vanished Space must never fall back by index.
    @discardableResult
    func setCurrentConnection(displayID: String, key: String?, contextID: String?) -> Bool {
        guard canChangeSavedWorkspaces,
              displayLayout.displays.contains(where: { $0.id == displayID }) else { return false }
        let observation = workspaceObservation(includingUnselectedDisplays: true)
        var index: Int?
        if let key {
            guard let found = composerKeys(displayID, observation: observation)?.firstIndex(of: key) else {
                showWorkspaceFeedback(connectionCopy.vanished, kind: .failure); return false
            }
            index = found
        }
        var next = settings
        var contexts = next.contextPlan.contexts.sorted { $0.order < $1.order }
        let id: String
        if let contextID {
            guard contexts.contains(where: { $0.id == contextID }) else { return false }
            id = contextID
        } else {
            guard key != nil else { return false }
            id = "connection-" + UUID().uuidString
            var number = contexts.count + 1
            while contexts.contains(where: { $0.name == connectionCopy.connection(number) }) { number += 1 }
            contexts.append(.init(id: id, order: contexts.count + 1,
                name: connectionCopy.connection(number), displaySpaceIndexes: [:]))
            next.savedWorkspaces.assignAvailableShortcut(to: id)
        }
        let position = contexts.firstIndex { $0.id == id }!
        let old = contexts[position]
        var members = old.displaySpaceIndexes
        members[displayID] = index
        next.savedWorkspaces.bookmarks[id, default: [:]][displayID] = key
        if members.isEmpty {
            contexts.remove(at: position)
            next.savedWorkspaces.bookmarks.removeValue(forKey: id)
            next.savedWorkspaces.shortcutSlots.removeValue(forKey: id)
        } else {
            contexts[position] = .init(id: id, order: old.order, name: old.name, displaySpaceIndexes: members)
        }
        guard contexts != settings.contextPlan.contexts || next.savedWorkspaces.bookmarks != settings.savedWorkspaces.bookmarks else { return true }
        next.savedWorkspaces.initialized = true
        next.contextPlan.replaceContexts(contexts, currentContextID: next.contextPlan.currentContextID)
        return commitSavedWorkspaceChange(next, label: connectionCopy.updated(display: displayName(for: displayID), connection: old.name, cleared: key == nil))
    }

    /// Move/swap both cells in one checked write and one undo record. Never
    /// clear the source after a separate destination write: a failed write or
    /// a stale drag must leave both connections intact.
    @discardableResult
    func transferCurrentConnection(_ desktop: WorkspaceDesktopReference, from sourceID: String,
                                   to destinationID: String?, expectedDestinationKey: String?, copying: Bool) -> Bool {
        let displayID = desktop.displayID
        guard canChangeSavedWorkspaces,
              displayLayout.displays.contains(where: { $0.id == displayID }) else { return false }
        guard let source = settings.contextPlan.contexts.first(where: { $0.id == sourceID }),
              source.spaceIndex(for: displayID) != nil,
              settings.savedWorkspaces.bookmarks[sourceID]?[displayID] == desktop.key,
              destinationID.map({ id in settings.contextPlan.contexts.contains { $0.id == id }
                  && settings.savedWorkspaces.bookmarks[id]?[displayID] == expectedDestinationKey }) ?? (expectedDestinationKey == nil)
        else { showWorkspaceFeedback(saveCopy.conflict, kind: .failure); return false }
        guard let keys = composerKeys(displayID, observation: workspaceObservation(includingUnselectedDisplays: true)),
              let index = keys.firstIndex(of: desktop.key) else { showWorkspaceFeedback(connectionCopy.vanished, kind: .failure); return false }
        if sourceID == destinationID { return true }
        if copying { return setCurrentConnection(displayID: displayID, key: desktop.key, contextID: destinationID) }

        let destination = destinationID.flatMap { id in settings.contextPlan.contexts.first { $0.id == id } }
        let reverseIndex = expectedDestinationKey.flatMap { keys.firstIndex(of: $0) }
        // A filled target swaps back into the source. Do not silently discard a
        // missing or legacy assignment that cannot be safely resolved by key.
        if destination?.spaceIndex(for: displayID) != nil && reverseIndex == nil {
            showWorkspaceFeedback(connectionCopy.vanished, kind: .failure); return false
        }
        var next = settings
        var contexts = next.contextPlan.contexts.sorted { $0.order < $1.order }
        let targetID = destinationID ?? "connection-" + UUID().uuidString
        if destinationID == nil {
            var number = contexts.count + 1
            while contexts.contains(where: { $0.name == connectionCopy.connection(number) }) { number += 1 }
            contexts.append(.init(id: targetID, order: contexts.count + 1,
                                  name: connectionCopy.connection(number), displaySpaceIndexes: [:]))
        }
        func assign(_ id: String, key: String?, index: Int?) {
            let position = contexts.firstIndex { $0.id == id }!
            let old = contexts[position]
            var members = old.displaySpaceIndexes
            members[displayID] = index
            next.savedWorkspaces.bookmarks[id, default: [:]][displayID] = key
            contexts[position] = .init(id: old.id, order: old.order, name: old.name, displaySpaceIndexes: members)
        }
        assign(sourceID, key: expectedDestinationKey, index: reverseIndex)
        assign(targetID, key: desktop.key, index: index)
        if contexts.first(where: { $0.id == sourceID })?.displayIDs.isEmpty == true {
            contexts.removeAll { $0.id == sourceID }
            next.savedWorkspaces.bookmarks.removeValue(forKey: sourceID)
            next.savedWorkspaces.shortcutSlots.removeValue(forKey: sourceID)
        }
        if destinationID == nil { next.savedWorkspaces.assignAvailableShortcut(to: targetID) }
        guard contexts != settings.contextPlan.contexts || next.savedWorkspaces.bookmarks != settings.savedWorkspaces.bookmarks else { return true }
        next.savedWorkspaces.initialized = true
        next.contextPlan.replaceContexts(contexts, currentContextID: next.contextPlan.currentContextID)
        let targetName = contexts.first(where: { $0.id == targetID })?.name ?? connectionCopy.add
        return commitSavedWorkspaceChange(next, label: connectionCopy.transferred(display: displayName(for: displayID), from: source.name, to: targetName, swapped: expectedDestinationKey != nil))
    }
}

struct CurrentConnectionStrings {
    let language: AppLanguage
    func text(_ en: String, _ ko: String) -> String { language == .korean ? ko : en }
    var title: String { text("Space connections", "Space 연결") }
    var editing: String { text("Edit connections", "연결 수정") }
    var hint: String { text("Click a cell to edit. Use Move together to switch displays.", "칸을 눌러 연결을 편집하세요. 화면 이동은 ‘함께 이동’을 누르세요.") }
    var scope: String { text("Only connections change. Spaces and app windows stay as they are.", "연결만 바뀝니다. 실제 Space와 앱 창은 그대로입니다.") }
    var dragHint: String { text("Same display: drag to move or swap · ⌥ Option-drag to copy", "같은 모니터의 칸끼리: 드래그로 이동·자리 바꾸기 · ⌥ Option + 드래그로 복사") }
    var applied: String { text("Connection updated. You can undo it.", "연결을 반영했어요. 되돌릴 수 있습니다.") }
    var notApplied: String { text("Change not applied", "변경을 반영하지 못했어요") }
    func updated(display: String, connection: String, cleared: Bool) -> String {
        cleared ? text("\(display) · Removed from ‘\(connection)’.", "\(display) · ‘\(connection)’에서 연결을 해제했어요.")
            : text("\(display) · Updated ‘\(connection)’.", "\(display) · ‘\(connection)’ 연결을 바꿨어요.")
    }
    func transferred(display: String, from: String, to: String, swapped: Bool) -> String {
        swapped ? text("\(display) · Swapped ‘\(from)’ and ‘\(to)’.", "\(display) · ‘\(from)’와 ‘\(to)’의 자리를 바꿨어요.")
            : text("\(display) · Moved from ‘\(from)’ to ‘\(to)’.", "\(display) · ‘\(from)’에서 ‘\(to)’로 옮겼어요.")
    }
    var vanished: String { text("That Space is no longer available. Choose again from the current list.", "해당 Space가 사라졌어요. 현재 목록에서 다시 골라 주세요.") }
    var choose: String { text("Choose Space", "Space 선택") }
    var add: String { text("Add connection", "연결 추가") }
    var createByDropping: String { text("Drop a Space to create", "Space를 놓으면 새 연결이 생겨요") }
    var dropHere: String { text("Drop a Space here", "여기로 끌어 놓기") }
    var orChoose: String { text("Or click to choose", "또는 눌러서 선택") }
    var start: String { text("Connect in current order", "현재 순서로 연결") }
    var empty: String { text("Start with the Spaces already open.", "이미 열어 둔 Space로 시작하세요.") }
    var emptyDetail: String { text("Pairs Spaces in the same order across your selected displays. Adjust any cell afterward.", "선택한 모니터의 Space를 같은 순서끼리 연결합니다. 다른 짝을 원하면 해당 칸만 바꾸세요.") }
    var repair: String { text("Space missing · Choose again", "Space 사라짐 · 다시 선택") }
    var keep: String { text("Leave this display as it is", "이 모니터는 그대로 두기") }
    var displays: String { text("Displays", "함께 움직일 모니터") }
    var offline: String { text("Disconnected · Kept", "연결 해제됨 · 정보 유지") }
    var excluded: String { text("Excluded from switching", "전환에서 제외됨") }
    var move: String { text("Go to this connection", "이 연결로 이동") }
    var moveTogether: String { text("Move together", "함께 이동") }
    var undo: String { text("Undo connection change", "연결 변경 되돌리기") }
    var readUnavailable: String { text("Couldn't read Spaces. Check your displays and refresh.", "Space를 읽지 못했어요. 모니터 연결을 확인한 뒤 새로고침하세요.") }
    /// Position in this display's Space list, not a Mission Control desktop name.
    func spacePosition(_ index: Int) -> String { text("Space · position \(index + 1)", "\(index + 1)번째 Space") }
    func connection(_ index: Int) -> String { text("Connection \(index)", "연결 \(index)") }
}
