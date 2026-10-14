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

    /// Capture the currently visible Space on every participating, connected display
    /// in one write. Never switch screens or silently save only part of the selection.
    @discardableResult
    func addCurrentConnection() -> String? {
        guard canChangeSavedWorkspaces else { return nil }
        let included = Set(displayLayout.displays.map(\.id)).intersection(selectedDisplayIDs)
        guard !included.isEmpty else {
            showWorkspaceFeedback(connectionCopy.chooseDisplays, kind: .failure); return nil
        }
        guard let observation = workspaceObservation(includingUnselectedDisplays: true) else {
            showWorkspaceFeedback(saveCopy.readUnavailable, kind: .failure); return nil
        }
        var members: [String: Int] = [:]
        var bookmarks: [String: String] = [:]
        for id in included {
            guard let key = durableCurrentKey(id, observation: observation),
                  let display = observation.displays.first(where: { $0.displayID == id }) else {
                showWorkspaceFeedback(saveCopy.readUnavailable, kind: .failure); return nil
            }
            members[id] = display.currentSpaceIndex
            bookmarks[id] = key
        }
        if let existing = settings.contextPlan.contexts.first(where: {
            Set($0.displayIDs) == included && settings.savedWorkspaces.bookmarks[$0.id] == bookmarks
        }) {
            showWorkspaceFeedback(connectionCopy.alreadyConnected(existing.name), kind: .notice)
            return existing.id
        }
        var next = settings
        let id = "connection-" + UUID().uuidString
        let name = currentConnectionName(members: members, bookmarks: bookmarks, observation: observation)
        let context = ContextDefinition(id: id, order: next.contextPlan.contexts.count + 1,
                                        name: name, displaySpaceIndexes: members)
        next.contextPlan.replaceContexts(next.contextPlan.contexts + [context], currentContextID: next.contextPlan.currentContextID)
        next.savedWorkspaces.initialized = true
        next.savedWorkspaces.bookmarks[id] = bookmarks
        next.savedWorkspaces.assignAvailableShortcut(to: id)
        guard commitSavedWorkspaceChange(next, label: connectionCopy.addedCurrent(name)) else { return nil }
        return id
    }

    /// Name the captured pair once; later title refreshes must not rename it.
    private func currentConnectionName(members: [String: Int], bookmarks: [String: String],
                                       observation: WorkspaceLayoutObservation) -> String {
        let ordered = WorkspaceTablePresentation.displayIDs(connected: displayLayout.displays.map(\.id),
            remembered: [], assigned: [], order: settings.displayRowOrder, includeDisconnected: false)
            .filter { members[$0] != nil }
        let names = ordered.map { id -> String in
            let index = members[id]!
            let alias = bookmarks[id].flatMap { DesktopNameIdentity(spaceKey: $0, displayID: id) }
                .flatMap { workspaceDesktopAliases[$0.storageKey] }
            // Cached titles belong to Space identities, not their old list positions.
            let handle = observation.spaceIDsByDisplayID[id]?[index]
            let cachedIndex = handle.flatMap { workspaceDesktopNameSpaceIDs[id]?.firstIndex(of: $0) }
            let title = cachedIndex.flatMap { workspaceDesktopNames[id]?[$0] }
            let name = (alias ?? title ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
            return name.isEmpty ? connectionCopy.spacePosition(index) : name
        }
        // Keep a part from each display when window titles are long, within the rename field's limit.
        let budget = max(1, (60 - max(0, names.count - 1) * 3) / max(1, names.count))
        let base = String(names.map { name in
            name.count > budget ? String(name.prefix(max(0, budget - 1))) + "…" : name
        }.joined(separator: " / ").prefix(60))
        let existing = Set(settings.contextPlan.contexts.map(\.name))
        var candidate = base, number = 2
        while existing.contains(candidate) {
            let suffix = " (\(number))"
            candidate = String(base.prefix(60 - suffix.count)) + suffix
            number += 1
        }
        return candidate
    }

    @discardableResult
    func renameCurrentConnection(_ id: String, originalName: String, name: String) -> Bool {
        guard canChangeSavedWorkspaces else { return false }
        guard case let .valid(value) = DesktopNameValidation.validate(name) else {
            showWorkspaceFeedback(connectionCopy.invalidName, kind: .failure); return false
        }
        guard let current = settings.contextPlan.contexts.first(where: { $0.id == id }), current.name == originalName else {
            showWorkspaceFeedback(connectionCopy.renameConflict, kind: .failure); return false
        }
        guard value != current.name else { return true }
        var next = settings
        next.contextPlan.renameContext(id: id, name: value)
        return commitSavedWorkspaceChange(next, label: connectionCopy.renamed(value))
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
              key == nil || displayLayout.displays.contains(where: { $0.id == displayID }) else { return false }
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
        let label = connectionCopy.updated(display: displayName(for: displayID), connection: old.name, cleared: key == nil)
            + (members.isEmpty ? connectionCopy.text(" The empty column was removed.", " 빈 연결 열도 삭제했습니다.") : "")
        return commitSavedWorkspaceChange(next, label: label)
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
            showWorkspaceFeedback(connectionCopy.missingSwapTarget, kind: .failure); return false
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
    var addCurrent: String { text("Connect current Spaces", "지금 화면으로 연결 추가") }
    var rename: String { text("Rename connection", "연결 이름 수정") }
    var invalidName: String { text("Enter a single-line name between 1 and 60 characters.", "이름을 1~60자의 한 줄로 입력해 주세요.") }
    var renameConflict: String { text("This connection changed. Close and reopen the name editor.", "이 연결이 변경됐어요. 이름 수정을 닫고 다시 열어 주세요.") }
    func renamed(_ name: String) -> String { text("Renamed to ‘\(name)’.", "‘\(name)’로 이름을 바꿨어요.") }
    var addCurrentHint: String { text("Add the Space currently visible on each participating display as one connection. Your screens stay where they are.", "함께 움직일 모니터에서 지금 보고 있는 Space들을 하나의 연결로 추가합니다. 화면은 이동하지 않습니다.") }
    var chooseDisplays: String { text("Choose participating displays in Edit connections first.", "연결 수정에서 함께 움직일 모니터를 먼저 선택해 주세요.") }
    func addedCurrent(_ name: String) -> String { text("Current Spaces added as \(name).", "지금 화면을 ‘\(name)’로 연결했어요.") }
    func alreadyConnected(_ name: String) -> String { text("Already connected as \(name).", "이미 ‘\(name)’로 연결되어 있어요.") }
    var editing: String { text("Edit connections", "연결 수정") }
    var hint: String { text("Click a cell to edit. Use Go together to switch displays.", "칸을 눌러 연결을 편집하세요. 화면 이동은 ‘함께 이동’을 누르세요.") }
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
    var vanished: String { text("That Space can't be found in the current list. Choose again.", "현재 목록에서 해당 Space를 찾을 수 없어요. 다시 골라 주세요.") }
    var missingSwapTarget: String { text("The destination Space can't be found, so it can't be swapped. Option-drag to copy here, or disconnect this cell first.", "대상 Space를 찾을 수 없어 자리를 바꿀 수 없어요. Option 드래그로 복사하거나 이 칸의 연결을 먼저 해제해 주세요.") }
    var choose: String { text("Choose Space", "Space 선택") }
    var add: String { text("Add connection", "연결 추가") }
    var createByDropping: String { text("Drop a Space to create", "Space를 놓으면 새 연결이 생겨요") }
    var dropHere: String { text("Drop a Space here", "여기로 끌어 놓기") }
    var orChoose: String { text("Or click to choose", "또는 눌러서 선택") }
    var start: String { text("Connect in current order", "현재 순서로 연결") }
    var empty: String { text("Start with the Spaces already open.", "이미 열어 둔 Space로 시작하세요.") }
    var emptyDetail: String { text("Pairs Spaces in the same order across your selected displays. Adjust any cell afterward.", "선택한 모니터의 Space를 같은 순서끼리 연결합니다. 다른 짝을 원하면 해당 칸만 바꾸세요.") }
    var emptyDirectHint: String { text("Choose a Space in an empty cell to make your first connection.", "빈 칸에서 Space를 골라 첫 연결을 만드세요.") }
    var emptyDragHint: String { text("Drop a Space into an empty cell, or click to choose.", "빈 칸에 Space를 놓거나, 칸을 눌러 골라 주세요.") }
    var repair: String { text("Space not found · Choose again", "Space 찾을 수 없음 · 다시 선택") }
    var repairHint: String { text("The saved Space can't be found. Choose another Space, or disconnect this cell below.", "저장한 Space를 현재 찾을 수 없어요. 다른 Space를 고르거나 아래에서 이 칸의 연결을 해제하세요.") }
    var keep: String { text("Leave this display as it is", "이 모니터는 그대로 두기") }
    var clearCell: String { text("Disconnect this cell", "이 칸 연결 해제") }
    var clearDisplay: String { text("Clear connections for this display…", "이 모니터의 연결 비우기…") }
    var displays: String { text("Displays", "함께 움직일 모니터") }
    var offline: String { text("Disconnected · Kept", "연결 해제됨 · 정보 유지") }
    var excluded: String { text("Excluded from switching", "전환에서 제외됨") }
    var move: String { text("Go to this connection", "이 연결로 이동") }
    var moveTogether: String { text("Go together", "함께 이동") }
    var undo: String { text("Undo connection change", "연결 변경 되돌리기") }
    var clearAll: String { text("Clear all connections…", "연결 모두 비우기…") }
    var clearAllAction: String { text("Clear connections", "연결 비우기") }
    func clearedAll(_ count: Int) -> String { text("Cleared \(count) connections. You can undo this.", "연결 \(count)개를 비웠어요. 되돌릴 수 있습니다.") }
    func clearAllTitle(_ count: Int) -> String { text("Clear all \(count) connections?", "연결 \(count)개를 모두 비울까요?") }
    var undoHistoryHint: String { text("Undo keeps the last 20 connection changes, including after restarting Sideby.", "앱을 다시 열어도 최근 연결 변경 20단계까지 되돌릴 수 있습니다.") }
    var clearAllMessage: String { text("Includes connections on disconnected displays. Your Spaces, open apps and other settings stay as they are.", "연결 해제된 모니터의 연결도 함께 비웁니다. 실제 Space와 열린 앱, 다른 설정은 그대로입니다.") + " " + undoHistoryHint }
    var readAgain: String { text("Read again", "다시 읽기") }
    var readUnavailable: String { text("Couldn't read Spaces. Check your display connections.", "Space를 읽지 못했어요. 모니터 연결을 확인해 주세요.") }
    /// Position in this display's Space list, not a Mission Control desktop name.
    func spacePosition(_ index: Int) -> String { text("Space · position \(index + 1)", "\(index + 1)번째 Space") }
    func connection(_ index: Int) -> String { text("Connection \(index)", "연결 \(index)") }
}
