import AppKit
import SidebyCore
import SidebyUI

struct WorkspaceSaveDraft: Identifiable, Equatable {
    let id = UUID()
    let editingID: String?
    let original: ContextDefinition?
    let originalBookmarks: [String: String]
    var name: String
    var members: [String: Int]
    var bookmarks: [String: String]
    var observation: WorkspaceLayoutObservation?
    var error: String?
    var duplicateID: String?
    var usesCurrentPositions: Bool
}

struct WorkspaceDeleteAllProposal: Equatable {
    let contexts: [ContextDefinition]
    let bookmarks: [String: [String: String]]
}

extension SidebyAppModel {
    var saveCopy: WorkspaceSaveStrings { .init(language: settings.language) }
    var canSaveWorkspace: Bool {
        canAddContext && pendingContextCaptureAlignment == nil && !settingsStore.hasUnreadableSettings
    }

    /// Direct menu mutations must not invalidate an open editor's baseline.
    var canChangeSavedWorkspaces: Bool {
        canSaveWorkspace && workspaceSaveDraft == nil && !hasWorkspaceComposerChanges
    }

    var availableWorkspaceChooserShortcut: String? {
        guard heldMatrixConfiguration.isEnabled, heldMatrixShortcutError == nil else { return nil }
        return KeyboardShortcutFormatter.shortcutText(heldMatrixConfiguration.shortcut)
    }

    func workspaceUnavailableReason(_ context: ContextDefinition) -> String {
        let connected = Set(connectedWorkspaceDisplayIDs).intersection(context.displayIDs)
        if connected.isEmpty { return saveCopy.offline }
        if connected.isDisjoint(with: selectedDisplayIDs) { return saveCopy.excluded }
        return saveCopy.text("Check desktop connection", "데스크탑 연결 확인 필요")
    }

    /// One-time import retains every old task, including offline and unassigned tasks.
    /// Existing saved identities take priority over a currently reused desktop index.
    @discardableResult
    func initializeSavedWorkspaceLibrary(_ observation: WorkspaceLayoutObservation?) -> Bool {
        guard !settings.savedWorkspaces.initialized else { return true }
        guard !settingsStore.hasUnreadableSettings, observation != nil || settings.contextPlan.contexts.isEmpty else { return false }
        var next = settings
        var library = next.savedWorkspaces
        let contexts = next.contextPlan.contexts.sorted { $0.order < $1.order }
        let connected = Set(displayLayout.displays.map(\.id)).union(selectedDisplayIDs)
        let priorVisible = contexts.filter { !Set($0.displayIDs).isDisjoint(with: connected) }
        for context in priorVisible + contexts.filter({ !priorVisible.contains($0) }) {
            library.assignAvailableShortcut(to: context.id)
            for (displayID, index) in context.displaySpaceIndexes {
                let keys = workspaceLastObservedSpaceKeys[displayID] ?? (workspaceIdentityNeedsReview ? nil : observation?.spaceKeysByDisplayID[displayID])
                if let keys, keys.indices.contains(index), Set(keys).count == keys.count {
                    library.bookmarks[context.id, default: [:]][displayID] = keys[index]
                } else if !workspaceIdentityNeedsReview, workspaceLastObservedSpaceKeys[displayID] == nil,
                          let ids = workspaceLastObservedSpaceIDs[displayID] ?? observation?.spaceIDsByDisplayID[displayID], ids.indices.contains(index) {
                    // Legacy sessions without UUIDs can still track their old live handles in memory.
                    // These handles are never written to settings or used to save a new workspace.
                    workspaceLegacyRuntimeBookmarks[context.id, default: [:]][displayID] = ids[index]
                }
            }
        }
        library.initialized = true
        next.savedWorkspaces = library
        guard settingsStore.saveChecked(next) else { return false }
        settings = next
        return true
    }

    func reconcileSavedWorkspaceLayout(_ observation: WorkspaceLayoutObservation?) -> Bool {
        workspaceLatestObservation = observation
        guard canAddContext, pendingContextCaptureAlignment == nil, let observation,
              initializeSavedWorkspaceLibrary(observation) else { return false }
        var next = settings
        var contexts = next.savedWorkspaces.resolved(next.contextPlan.contexts, spaceKeys: observation.spaceKeysByDisplayID)
        for index in contexts.indices {
            let context = contexts[index]
            var members = context.displaySpaceIndexes
            for (id, handle) in workspaceLegacyRuntimeBookmarks[context.id] ?? [:]
                where members[id] != nil && next.savedWorkspaces.bookmarks[context.id]?[id] == nil {
                // Keep legacy handles for undo, but never restore a removed member during refresh.
                if let position = observation.spaceIDsByDisplayID[id]?.firstIndex(of: handle) { members[id] = position }
            }
            contexts[index] = .init(id: context.id, order: context.order, name: context.name, displaySpaceIndexes: members)
        }
        if contexts != next.contextPlan.contexts {
            let pinned = next.contextPlan.isPinned
            next.contextPlan.replaceContexts(contexts, currentContextID: next.contextPlan.currentContextID)
            next.contextPlan.setPinned(pinned)
            guard settingsStore.saveChecked(next) else { return false }
            settings = next
            workspaceConfigurationRevision += 1
        }
        workspaceLastObservedSpaceIDs.merge(observation.spaceIDsByDisplayID) { _, new in new }
        workspaceLastObservedSpaceKeys.merge(observation.spaceKeysByDisplayID) { _, new in new }
        reconcileWorkspaceDesktopNames(observation)
        return true
    }

    func unresolvedWorkspaceMembers(_ context: ContextDefinition, observation: WorkspaceLayoutObservation? = nil) -> Set<String> {
        guard settings.savedWorkspaces.initialized else { return [] }
        let observation = observation ?? workspaceLatestObservation ?? WorkspaceLayoutObservation(displays: [], spaceIDsByDisplayID: [:])
        let connected = selectedDisplayIDs
        var invalid = settings.savedWorkspaces.unavailableMembers(of: context, connectedIDs: connected,
            spaceKeys: observation.spaceKeysByDisplayID)
        for id in invalid where settings.savedWorkspaces.bookmarks[context.id]?[id] == nil {
            if let handle = workspaceLegacyRuntimeBookmarks[context.id]?[id],
               let index = context.spaceIndex(for: id), let ids = observation.spaceIDsByDisplayID[id],
               ids.indices.contains(index), ids[index] == handle { invalid.remove(id) }
        }
        return invalid
    }

    func workspaceShortcut(_ id: String) -> String? {
        guard let slot = settings.savedWorkspaces.shortcutSlots[id],
              !failedContextKeyboardCommands.contains(.activate(position: slot)) else { return nil }
        return "⌥⇧\(slot == 10 ? 0 : slot)"
    }

    func prepareWorkspaceSave(editingID: String? = nil) -> WorkspaceSaveDraft? {
        guard canSaveWorkspace else { return nil }
        refreshWorkspaceStatus()
        let observation = workspaceObservation(includingUnselectedDisplays: true)
        _ = initializeSavedWorkspaceLibrary(observation)
        let original = settings.contextPlan.contexts.first { $0.id == editingID }
        if editingID != nil && original == nil { return nil }
        let bookmarks = original.flatMap { settings.savedWorkspaces.bookmarks[$0.id] } ?? [:]
        var members = original?.displaySpaceIndexes ?? [:]
        var draftBookmarks = bookmarks
        if original == nil {
            let included = defaultWorkspaceSaveDisplays(observation)
            for display in observation?.displays ?? [] where included.contains(display.displayID) {
                guard let key = durableCurrentKey(display.displayID, observation: observation) else { continue }
                members[display.displayID] = display.currentSpaceIndex
                draftBookmarks[display.displayID] = key
            }
        }
        let names = Set(settings.contextPlan.contexts.map(\.name))
        var number = 1
        while names.contains(saveCopy.defaultName(number)) { number += 1 }
        return WorkspaceSaveDraft(editingID: editingID, original: original, originalBookmarks: bookmarks,
            name: original?.name ?? saveCopy.defaultName(number), members: members, bookmarks: draftBookmarks,
            observation: observation, error: original == nil && members.isEmpty ? saveCopy.readUnavailable : nil,
            usesCurrentPositions: original == nil)
    }

    private func defaultWorkspaceSaveDisplays(_ observation: WorkspaceLayoutObservation?) -> Set<String> {
        let available = Set(observation?.displays.map(\.displayID) ?? []).intersection(selectedDisplayIDs)
        let remembered = Set(settings.savedWorkspaces.lastIncludedDisplayIDs ?? []).intersection(available)
        return remembered.isEmpty ? available : remembered
    }

    func durableCurrentKey(_ id: String, observation: WorkspaceLayoutObservation?) -> String? {
        guard let display = observation?.displays.first(where: { $0.displayID == id }),
              let keys = observation?.spaceKeysByDisplayID[id], let ids = observation?.spaceIDsByDisplayID[id],
              keys.count == display.spaceCount, ids.count == keys.count, Set(keys).count == keys.count, keys.allSatisfy({ !$0.isEmpty }),
              keys.indices.contains(display.currentSpaceIndex) else { return nil }
        return keys[display.currentSpaceIndex]
    }

    func refreshWorkspaceSaveDraft() {
        guard var draft = workspaceSaveDraft else { return }
        let observation = workspaceObservation(includingUnselectedDisplays: true)
        guard observation != nil else { draft.error = saveCopy.readUnavailable; workspaceSaveDraft = draft; return }
        if draft.editingID == nil && draft.members.isEmpty,
           draft.observation == nil || draft.error == saveCopy.readUnavailable {
            let included = defaultWorkspaceSaveDisplays(observation)
            for id in included {
                if let display = observation?.displays.first(where: { $0.displayID == id }) { draft.members[id] = display.currentSpaceIndex }
            }
        }
        draft.observation = observation
        for id in draft.members.keys {
            if let key = durableCurrentKey(id, observation: observation),
               let display = observation?.displays.first(where: { $0.displayID == id }) {
                draft.members[id] = display.currentSpaceIndex
                draft.bookmarks[id] = key
            }
        }
        draft.usesCurrentPositions = true
        draft.error = nil
        draft.duplicateID = nil
        workspaceSaveDraft = draft
    }

    func setWorkspaceDraftDisplay(_ id: String, included: Bool) {
        guard var draft = workspaceSaveDraft else { return }
        if included {
            if let n = draft.original?.spaceIndex(for: id), draft.observation?.displays.contains(where: { $0.displayID == id }) != true {
                draft.members[id] = n
                draft.bookmarks[id] = draft.originalBookmarks[id]
            } else if let key = durableCurrentKey(id, observation: draft.observation),
                      let display = draft.observation?.displays.first(where: { $0.displayID == id }) {
                draft.members[id] = display.currentSpaceIndex
                draft.bookmarks[id] = key
            }
        } else { draft.members.removeValue(forKey: id); draft.bookmarks.removeValue(forKey: id) }
        draft.error = nil; draft.duplicateID = nil
        workspaceSaveDraft = draft
    }

    func setWorkspaceDraftDesktop(_ id: String, index: Int) {
        guard var draft = workspaceSaveDraft, let keys = draft.observation?.spaceKeysByDisplayID[id],
              keys.indices.contains(index), Set(keys).count == keys.count else { return }
        draft.members[id] = index
        draft.bookmarks[id] = keys[index]
        draft.usesCurrentPositions = false
        draft.error = nil; draft.duplicateID = nil
        workspaceSaveDraft = draft
    }

    @discardableResult
    func commitWorkspaceSave() -> Bool {
        guard var draft = workspaceSaveDraft, canSaveWorkspace else { return false }
        func fail(_ message: String, duplicateID: String? = nil) -> Bool {
            draft.error = message; draft.duplicateID = duplicateID; workspaceSaveDraft = draft; return false
        }
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 60, !draft.members.isEmpty else { return fail(saveCopy.invalidNameOrSelection) }
        guard let observation = workspaceObservation(includingUnselectedDisplays: true) else { return fail(saveCopy.readUnavailable) }
        if let id = draft.editingID {
            guard let current = settings.contextPlan.contexts.first(where: { $0.id == id }),
                  current.name == draft.original?.name, current.order == draft.original?.order,
                  current.displayIDs == draft.original?.displayIDs,
                  settings.savedWorkspaces.bookmarks[id, default: [:]] == draft.originalBookmarks else { return fail(saveCopy.conflict) }
        }
        var members = draft.members
        let liveIDs = Set(observation.displays.map(\.displayID))
        for (id, oldIndex) in draft.members {
            let unchanged = draft.original?.spaceIndex(for: id) == oldIndex && draft.originalBookmarks[id] == draft.bookmarks[id]
            guard let keys = observation.spaceKeysByDisplayID[id] else {
                if unchanged && !liveIDs.contains(id) { continue }
                return fail(saveCopy.changed)
            }
            guard Set(keys).count == keys.count, let key = draft.bookmarks[id], let index = keys.firstIndex(of: key) else {
                // Rename-only edits may preserve a previously missing target; never repair it by index.
                if unchanged && !draft.usesCurrentPositions { continue }
                return fail(saveCopy.changed)
            }
            if draft.usesCurrentPositions, observation.displays.first(where: { $0.displayID == id })?.currentSpaceIndex != index {
                return fail(saveCopy.changed)
            }
            members[id] = index
        }
        if let duplicate = settings.contextPlan.contexts.first(where: {
            $0.id != draft.editingID && Set($0.displayIDs) == Set(members.keys)
                && settings.savedWorkspaces.bookmarks[$0.id] == draft.bookmarks
                && draft.bookmarks.count == members.count
        }) { return fail(saveCopy.duplicate(duplicate.name), duplicateID: duplicate.id) }
        let id = draft.editingID ?? "workspace-" + UUID().uuidString
        var next = settings
        let context = ContextDefinition(id: id, order: draft.original?.order ?? next.contextPlan.contexts.count + 1,
                                        name: name, displaySpaceIndexes: members)
        var contexts = next.contextPlan.contexts
        if let index = contexts.firstIndex(where: { $0.id == id }) { contexts[index] = context }
        else { contexts.append(context) }
        guard contexts != settings.contextPlan.contexts || next.savedWorkspaces.bookmarks[id] != draft.bookmarks else { return true }
        next.contextPlan.replaceContexts(contexts, currentContextID: next.contextPlan.currentContextID)
        next.savedWorkspaces.bookmarks[id] = draft.bookmarks
        next.savedWorkspaces.assignAvailableShortcut(to: id)
        if draft.editingID == nil { next.savedWorkspaces.lastIncludedDisplayIDs = members.keys.sorted() }
        guard commitSavedWorkspaceChange(next, label: draft.editingID == nil ? saveCopy.saved(name) : saveCopy.edited(name)) else {
            return fail(saveCopy.saveFailed)
        }
        workspaceSavedFocusID = id
        return true
    }

    @discardableResult
    func commitSavedWorkspaceChange(_ candidate: AppSettings, label: String) -> Bool {
        var next = candidate
        next.savedWorkspaces.undo = SavedWorkspaceUndo(contexts: settings.contextPlan.contexts,
            bookmarks: settings.savedWorkspaces.bookmarks, shortcutSlots: settings.savedWorkspaces.shortcutSlots,
            label: label, resultingContexts: next.contextPlan.contexts, resultingBookmarks: next.savedWorkspaces.bookmarks)
        guard settingsStore.saveChecked(next) else { workspaceSaveMessage = saveCopy.saveFailed; return false }
        applySavedWorkspaceChange(next)
        workspaceSaveMessage = label
        return true
    }

    func applySavedWorkspaceChange(_ next: AppSettings) {
        settings = next
        workspaceConfigurationRevision += 1
        workspaceHistory.reconcile(validContextIDs: Set(next.contextPlan.contexts.map(\.id)))
        firstWorkProgress.reconcile(validContextIDs: Set(next.contextPlan.contexts.map(\.id)))
        verifiedCurrentWorkspaceID = nil
        workspaceRecoveryTargetID = nil
        applyWorkspaceObservation(workspaceObservation())
        saveWorkspaceIdentitySnapshot()
    }

    @discardableResult
    func deleteSavedWorkspace(_ id: String) -> Bool {
        guard canChangeSavedWorkspaces, let context = settings.contextPlan.contexts.first(where: { $0.id == id }) else { return false }
        var next = settings
        next.contextPlan.replaceContexts(next.contextPlan.contexts.filter { $0.id != id }, currentContextID: next.contextPlan.currentContextID)
        next.savedWorkspaces.bookmarks.removeValue(forKey: id)
        next.savedWorkspaces.shortcutSlots.removeValue(forKey: id)
        return commitSavedWorkspaceChange(next, label: saveCopy.deleted(context.name))
    }

    var canDeleteAllSavedWorkspaces: Bool {
        canChangeSavedWorkspaces && !settings.contextPlan.contexts.isEmpty
    }

    func prepareDeleteAllSavedWorkspaces() -> WorkspaceDeleteAllProposal? {
        guard canDeleteAllSavedWorkspaces else { return nil }
        return .init(contexts: settings.contextPlan.contexts, bookmarks: settings.savedWorkspaces.bookmarks)
    }

    @discardableResult
    func deleteAllSavedWorkspaces(_ proposal: WorkspaceDeleteAllProposal) -> Bool {
        guard canDeleteAllSavedWorkspaces else { return false }
        // A confirmation must never delete work added or changed while it was open.
        guard settings.contextPlan.contexts == proposal.contexts,
              settings.savedWorkspaces.bookmarks == proposal.bookmarks else {
            workspaceSaveMessage = saveCopy.deleteAllChanged
            return false
        }
        var next = settings
        next.contextPlan.replaceContexts([], currentContextID: "")
        next.savedWorkspaces.bookmarks.removeAll()
        next.savedWorkspaces.shortcutSlots.removeAll()
        guard commitSavedWorkspaceChange(next, label: saveCopy.deletedAll(proposal.contexts.count)) else { return false }
        workspaceSavedFocusID = nil
        return true
    }

    @discardableResult
    func undoSavedWorkspaceChange() -> Bool {
        guard canChangeSavedWorkspaces, let undo = settings.savedWorkspaces.undo else { return false }
        // Index rebasing is an observation, not a new edit. Compare definitions by identity and name.
        let shape: ([ContextDefinition]) -> [String] = { $0.map { $0.id + "\u{0}" + $0.name + "\u{0}" + $0.displayIDs.joined(separator: "\u{0}") } }
        guard shape(settings.contextPlan.contexts) == shape(undo.resultingContexts),
              settings.savedWorkspaces.bookmarks == undo.resultingBookmarks else {
            workspaceSaveMessage = saveCopy.conflict; return false
        }
        var next = settings
        next.savedWorkspaces.bookmarks = undo.bookmarks
        next.savedWorkspaces.shortcutSlots = undo.shortcutSlots
        next.savedWorkspaces.undo = nil
        let contexts = next.savedWorkspaces.resolved(undo.contexts, spaceKeys: workspaceObservation()?.spaceKeysByDisplayID ?? [:])
        next.contextPlan.replaceContexts(contexts, currentContextID: next.contextPlan.currentContextID)
        guard settingsStore.saveChecked(next) else { workspaceSaveMessage = saveCopy.saveFailed; return false }
        applySavedWorkspaceChange(next)
        workspaceSaveMessage = saveCopy.undone
        return true
    }

    func showWorkspaceSave(editingID: String? = nil, anchor: NSRect? = nil, completion: (() -> Void)? = nil) {
        if hasWorkspaceComposerChanges {
            resolveWorkspaceComposerBeforeLeaving(window: nil) { [weak self] in
                self?.showWorkspaceSave(editingID: editingID, anchor: anchor, completion: completion)
            }
            return
        }
        if workspaceSaveDraft == nil { workspaceSaveDraft = prepareWorkspaceSave(editingID: editingID) }
        guard workspaceSaveDraft != nil else { workspaceSaveMessage = saveCopy.readUnavailable; return }
        if workspaceSaveController == nil { workspaceSaveController = WorkspaceSaveWindowController(model: self) }
        workspaceSaveController?.show(anchor: anchor, completion: completion)
    }
}
