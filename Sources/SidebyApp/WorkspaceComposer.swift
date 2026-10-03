import AppKit
import SidebyCore

/// A draft follows durable Space keys. Positions only describe unresolved legacy/offline members.
struct WorkspaceComposerMember: Equatable {
    var key: String?
    var index: Int

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.key == rhs.key && (lhs.key != nil || lhs.index == rhs.index)
    }
}

struct WorkspaceComposerEntry: Identifiable, Equatable {
    let id: String
    var name: String
    var members: [String: WorkspaceComposerMember]
}

struct WorkspaceComposerState: Equatable {
    var entries: [WorkspaceComposerEntry]
    var slots: [String: Int]

    init(settings: AppSettings) {
        entries = settings.contextPlan.contexts.sorted { $0.order < $1.order }.map { context in
            .init(id: context.id, name: context.name, members: context.displaySpaceIndexes.mapValues { .init(key: nil, index: $0) })
        }
        for i in entries.indices {
            let bookmarks = settings.savedWorkspaces.bookmarks[entries[i].id]
            for id in entries[i].members.keys {
                entries[i].members[id]?.key = bookmarks?[id]
            }
        }
        slots = settings.savedWorkspaces.shortcutSlots
    }

    mutating func move(_ id: String, relativeTo target: String, after: Bool) {
        guard id != target, let source = entries.firstIndex(where: { $0.id == id }),
              entries.contains(where: { $0.id == target }) else { return }
        let entry = entries.remove(at: source)
        let destination = entries.firstIndex(where: { $0.id == target })!
        entries.insert(entry, at: destination + (after ? 1 : 0))
    }
}

struct WorkspaceComposerDraft {
    var baseline: WorkspaceComposerState
    var state: WorkspaceComposerState
    var history: [WorkspaceComposerState] = []
    var observation: WorkspaceLayoutObservation?
    var desktopNames: [String: [String: String]] = [:]
    var error: String?
    var hasChanges: Bool { state != baseline }
}

struct WorkspaceDesktopReference: Codable, Equatable, Sendable {
    let displayID: String
    let key: String
}

/// Session-scoped transport prevents stale drags from a different composer or another app.
struct WorkspaceComposerDrag: Codable, Equatable, Sendable {
    let id: UUID
    let session: UUID
    var desktop: WorkspaceDesktopReference?
    var contextID: String?
    static let prefix = "sideby-composer|"
    var rawValue: String { Self.prefix + String(decoding: (try? JSONEncoder().encode(self)) ?? Data(), as: UTF8.self) }
    init(session: UUID, desktop: WorkspaceDesktopReference? = nil, contextID: String? = nil) {
        self.id = UUID(); self.session = session; self.desktop = desktop; self.contextID = contextID
    }
    init?(rawValue: String) {
        guard rawValue.hasPrefix(Self.prefix), let data = String(rawValue.dropFirst(Self.prefix.count)).data(using: .utf8),
              let value = try? JSONDecoder().decode(Self.self, from: data),
              (value.desktop != nil) != (value.contextID != nil),
              value.desktop.map({ !$0.displayID.isEmpty && !$0.key.isEmpty }) ?? !(value.contextID?.isEmpty ?? true)
        else { return nil }
        self = value
    }
}

extension SidebyAppModel {
    var canEditWorkspaceComposer: Bool { canSaveWorkspace && workspaceSaveDraft == nil }
    var hasWorkspaceComposerChanges: Bool { workspaceComposerDraft?.hasChanges == true }

    func beginWorkspaceComposer() {
        guard workspaceComposerDraft == nil else {
            refreshWorkspaceComposer()
            refreshWorkspaceComposerNames()
            return
        }
        refreshWorkspaceStatus()
        let observation = workspaceObservation(includingUnselectedDisplays: true)
        guard initializeSavedWorkspaceLibrary(observation) else { return }
        let state = WorkspaceComposerState(settings: settings)
        workspaceComposerDraft = .init(baseline: state, state: state, observation: observation)
        loadWorkspaceNamesIfNeeded()
        refreshWorkspaceComposerNames()
    }

    func refreshWorkspaceComposer() {
        guard var draft = workspaceComposerDraft else { return }
        let previous = draft.observation?.spaceIDsByDisplayID
        draft.observation = workspaceObservation(includingUnselectedDisplays: true)
        if !draft.hasChanges {
            draft.baseline = .init(settings: settings)
            draft.state = draft.baseline
            draft.history = []
        }
        workspaceComposerDraft = draft
        if previous != draft.observation?.spaceIDsByDisplayID { refreshWorkspaceComposerNames() }
    }

    func refreshWorkspaceComposerNames() {
        guard var draft = workspaceComposerDraft, let observation = draft.observation,
              let provider = workspaceNameSuggestionProvider else { return }
        let names = provider.names(for: displayLayout, spaceIDsByDisplayID: observation.spaceIDsByDisplayID)
        guard workspaceObservation(includingUnselectedDisplays: true)?.spaceIDsByDisplayID == observation.spaceIDsByDisplayID else { return }
        draft.desktopNames = [:]
        for (id, values) in names {
            guard let keys = composerKeys(id, observation: observation) else { continue }
            for (index, name) in values where keys.indices.contains(index) { draft.desktopNames[id, default: [:]][keys[index]] = name }
        }
        workspaceComposerDraft = draft
    }

    func workspaceComposerDesktopName(displayID: String, spaceIndex: Int) -> String? {
        guard let draft = workspaceComposerDraft,
              let observation = draft.observation,
              let keys = composerKeys(displayID, observation: observation), keys.indices.contains(spaceIndex) else { return nil }
        // The source tray shows live order, including excluded displays whose saved order may differ.
        if let identity = desktopAliasIdentities(in: observation)[displayID]?[spaceIndex],
           let alias = workspaceDesktopAliases[identity.storageKey] { return alias }
        if let name = draft.desktopNames[displayID]?[keys[spaceIndex]] { return name }
        // Reuse an earlier automatic name only for the same Space, never its former position.
        guard let handle = observation.spaceIDsByDisplayID[displayID]?[spaceIndex],
              let cachedIndex = workspaceDesktopNameSpaceIDs[displayID]?.firstIndex(of: handle) else { return nil }
        return workspaceDesktopNames[displayID]?[cachedIndex]
    }

    func discardWorkspaceComposer() {
        workspaceComposerDraft = nil
        beginWorkspaceComposer()
    }

    func editWorkspaceComposer(_ edit: (inout WorkspaceComposerState) -> Void) {
        guard canEditWorkspaceComposer, var draft = workspaceComposerDraft else { return }
        var state = draft.state
        edit(&state)
        guard state != draft.state else { return }
        draft.history.append(draft.state)
        if draft.history.count > 40 { draft.history.removeFirst() }
        draft.state = state; draft.error = nil
        workspaceComposerDraft = draft
    }

    func undoWorkspaceComposer() {
        guard canEditWorkspaceComposer, var draft = workspaceComposerDraft else { return }
        if let previous = draft.history.popLast() {
            draft.state = previous; draft.error = nil; workspaceComposerDraft = draft
        } else if !draft.hasChanges, undoSavedWorkspaceChange() { refreshWorkspaceComposer() }
    }

    func composerKeys(_ id: String, observation: WorkspaceLayoutObservation?) -> [String]? {
        guard displayLayout.displays.contains(where: { $0.id == id }),
              let display = observation?.displays.first(where: { $0.displayID == id }),
              let keys = observation?.spaceKeysByDisplayID[id],
              let handles = observation?.spaceIDsByDisplayID[id],
              keys.count == display.spaceCount, handles.count == keys.count,
              Set(keys).count == keys.count, keys.allSatisfy({ !$0.isEmpty }) else { return nil }
        return keys
    }

    @discardableResult
    func assignWorkspaceComposer(_ reference: WorkspaceDesktopReference, to contextID: String, displayID: String? = nil) -> Bool {
        guard canEditWorkspaceComposer, displayID == nil || displayID == reference.displayID,
              let observation = workspaceObservation(includingUnselectedDisplays: true),
              let keys = composerKeys(reference.displayID, observation: observation),
              let index = keys.firstIndex(of: reference.key),
              workspaceComposerDraft?.state.entries.contains(where: { $0.id == contextID }) == true else { return false }
        workspaceComposerDraft?.observation = observation
        editWorkspaceComposer { state in
            let i = state.entries.firstIndex { $0.id == contextID }!
            state.entries[i].members[reference.displayID] = .init(key: reference.key, index: index)
        }
        return true
    }

    func addWorkspaceComposer(name: String, useCurrent: Bool) -> String? {
        guard canEditWorkspaceComposer, workspaceComposerDraft != nil else { return nil }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 60 else { return nil }
        var members: [String: WorkspaceComposerMember] = [:]
        if useCurrent {
            let observation = workspaceObservation(includingUnselectedDisplays: true)
            for display in observation?.displays ?? [] where selectedDisplayIDs.contains(display.displayID) {
                guard let keys = composerKeys(display.displayID, observation: observation), keys.indices.contains(display.currentSpaceIndex) else { continue }
                members[display.displayID] = .init(key: keys[display.currentSpaceIndex], index: display.currentSpaceIndex)
            }
            guard !members.isEmpty else { workspaceComposerDraft?.error = saveCopy.readUnavailable; return nil }
            workspaceComposerDraft?.observation = observation
        }
        let id = "workspace-" + UUID().uuidString
        editWorkspaceComposer { state in
            state.entries.append(.init(id: id, name: name, members: members))
            state.slots[id] = (1...10).first { !state.slots.values.contains($0) }
        }
        return id
    }

    func workspaceComposerValidation(_ draft: WorkspaceComposerDraft) -> String? {
        for entry in draft.state.entries {
            let original = draft.baseline.entries.first { $0.id == entry.id }
            guard !entry.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, entry.name.count <= 60 else { return saveCopy.invalidNameOrSelection }
            // An imported empty/duplicate setup may still be renamed, reordered or deleted.
            if entry.members != original?.members {
                if entry.members.isEmpty { return saveCopy.text("Connect at least one desktop to ‘\(entry.name)’.", "‘\(entry.name)’에 데스크탑을 하나 이상 연결해 주세요.") }
                if entry.members.values.allSatisfy({ $0.key != nil }),
                   let duplicate = draft.state.entries.first(where: { $0.id != entry.id && $0.members == entry.members }) {
                    return saveCopy.duplicate(duplicate.name)
                }
            }
        }
        return nil
    }

    @discardableResult
    func commitWorkspaceComposer() -> Bool {
        guard canEditWorkspaceComposer, var draft = workspaceComposerDraft, draft.hasChanges else { return false }
        func fail(_ message: String) -> Bool { draft.error = message; workspaceComposerDraft = draft; return false }
        guard WorkspaceComposerState(settings: settings) == draft.baseline else { return fail(saveCopy.conflict) }
        if let error = workspaceComposerValidation(draft) { return fail(error) }
        let observation = workspaceObservation(includingUnselectedDisplays: true)
        var contexts: [ContextDefinition] = []
        var bookmarks: [String: [String: String]] = [:]
        for (order, entry) in draft.state.entries.enumerated() {
            let original = draft.baseline.entries.first { $0.id == entry.id }
            var indexes: [String: Int] = [:]
            for (id, member) in entry.members {
                let keys = composerKeys(id, observation: observation)
                let resolved = member.key.flatMap { keys?.firstIndex(of: $0) }
                if member != original?.members[id], resolved == nil { return fail(saveCopy.changed) }
                indexes[id] = resolved ?? member.index
                if let key = member.key { bookmarks[entry.id, default: [:]][id] = key }
            }
            contexts.append(.init(id: entry.id, order: order + 1, name: entry.name, displaySpaceIndexes: indexes))
        }
        var next = settings
        next.contextPlan.replaceContexts(contexts, currentContextID: next.contextPlan.currentContextID)
        next.savedWorkspaces.bookmarks = bookmarks
        next.savedWorkspaces.shortcutSlots = draft.state.slots.filter { id, _ in contexts.contains { $0.id == id } }
        guard commitSavedWorkspaceChange(next, label: saveCopy.text("Saved setup changes.", "구성 변경사항을 저장했어요.")) else { return fail(saveCopy.saveFailed) }
        let state = WorkspaceComposerState(settings: settings)
        workspaceComposerDraft = .init(baseline: state, state: state, observation: observation, desktopNames: draft.desktopNames)
        return true
    }

    /// Quick-matrix reorder is one immediately undoable edit; stable shortcut slots stay attached to IDs.
    @discardableResult
    func reorderSavedWorkspace(_ id: String, relativeTo target: String, after: Bool) -> Bool {
        guard canEditWorkspaceComposer, !hasWorkspaceComposerChanges else { return false }
        var state = WorkspaceComposerState(settings: settings)
        let previous = state
        state.move(id, relativeTo: target, after: after)
        guard state != previous else { return false }
        var next = settings
        next.contextPlan.replaceContexts(state.entries.enumerated().map { order, entry in
            .init(id: entry.id, order: order + 1, name: entry.name, displaySpaceIndexes: entry.members.mapValues(\.index))
        }, currentContextID: next.contextPlan.currentContextID)
        let saved = commitSavedWorkspaceChange(next, label: saveCopy.text("Setup order changed.", "구성 순서를 변경했어요."))
        if saved { refreshWorkspaceComposer() }
        return saved
    }
}

extension SidebyAppModel {
    func resolveWorkspaceComposerBeforeLeaving(window: NSWindow?, completion: @escaping @MainActor () -> Void) {
        guard hasWorkspaceComposerChanges else { completion(); return }
        guard window?.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.messageText = saveCopy.text("Save setup changes?", "구성 변경사항을 저장할까요?")
        alert.informativeText = saveCopy.text("Your desktop connections and setup order have unsaved changes.", "데스크탑 연결이나 구성 순서에 저장하지 않은 변경사항이 있습니다.")
        alert.addButton(withTitle: saveCopy.saveChanges)
        alert.addButton(withTitle: saveCopy.text("Keep editing", "계속 편집"))
        alert.addButton(withTitle: saveCopy.text("Discard changes", "저장 안 함"))
        alert.buttons[0].isEnabled = canEditWorkspaceComposer && workspaceComposerDraft.flatMap(workspaceComposerValidation) == nil
        alert.buttons[1].keyEquivalent = "\u{1b}"
        let respond: @MainActor (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            if response == .alertFirstButtonReturn {
                if self.commitWorkspaceComposer() { completion() }
            } else if response == .alertThirdButtonReturn {
                self.discardWorkspaceComposer(); completion()
            }
        }
        if let window { alert.beginSheetModal(for: window, completionHandler: respond) }
        else { respond(alert.runModal()) }
    }
}
