import Foundation
import SidebyCore

struct WorkspaceIdentitySnapshot: Codable, Equatable {
    let assignments: [String: [String: Int]]
    let spaceKeys: [String: [String]]

    init(plan: ContextPlan, spaceKeys: [String: [String]]) {
        assignments = Dictionary(uniqueKeysWithValues: plan.contexts.map { ($0.id, $0.displaySpaceIndexes) })
        self.spaceKeys = spaceKeys
    }

    func matches(_ plan: ContextPlan) -> Bool {
        assignments == Dictionary(uniqueKeysWithValues: plan.contexts.map { ($0.id, $0.displaySpaceIndexes) })
    }
}

struct WorkspaceRebuildBackup: Codable, Equatable {
    let plan: ContextPlan
    let nameOrigins: [String: String]
    let identity: WorkspaceIdentitySnapshot
}

struct WorkspaceRebuildProposal {
    let observation: WorkspaceLayoutObservation
    let selectedDisplayIDs: Set<String>
    let configurationRevision: Int
    var count: Int { observation.displays.map(\.spaceCount).max() ?? 0 }
}

enum WorkspaceRebuildPolicy {
    static func contexts(existing: [ContextDefinition], observation: WorkspaceLayoutObservation,
                         selectedDisplayIDs: Set<String>, names: [String: [Int: String]],
                         defaultName: (Int) -> String) -> [ContextDefinition]? {
        guard let fresh = WorkspaceLiveRefreshPolicy.contexts(existing: [], observation: observation,
            selectedDisplayIDs: selectedDisplayIDs, previousSpaceIDs: [:], defaultName: defaultName) else { return nil }
        let rebuilt = fresh.map { context in
            var contentNames: [String] = []
            for display in observation.displays {
                guard let index = context.spaceIndex(for: display.displayID),
                      let name = names[display.displayID]?[index]?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !name.isEmpty, !contentNames.contains(name) else { continue }
                contentNames.append(name)
            }
            return contentNames.isEmpty ? context : context.renamed(String(contentNames.joined(separator: " / ").prefix(160)))
        }
        // Preserve disconnected/excluded displays separately. Never reuse their
        // names or identifiers for newly created, position-based workspaces.
        let retained = existing.sorted { $0.order < $1.order }.compactMap { old -> ContextDefinition? in
            let mappings = old.displaySpaceIndexes.filter { !selectedDisplayIDs.contains($0.key) }
            guard !mappings.isEmpty else { return nil }
            return .init(id: old.id, order: rebuilt.count + old.order, name: old.name, displaySpaceIndexes: mappings)
        }
        return rebuilt + retained
    }
}

extension SidebyAppModel {
    static var identitySnapshotKey: String { "sideby.workspace-identities-v1" }
    static var rebuildBackupKey: String { "sideby.workspace-rebuild-backup-v1" }

    var workspaceKeyboardPlan: ContextPlan {
        WorkspaceContextVisibility.plan(settings.contextPlan,
            connectedDisplayIDs: Set(displayLayout.displays.map(\.id)).union(selectedDisplayIDs))
    }

    func loadWorkspacePersistence() {
        loadDesktopAliases()
        loadHeldMatrixConfiguration()
        if let data = workspacePreferences?.data(forKey: Self.identitySnapshotKey) {
            if let saved = try? JSONDecoder().decode(WorkspaceIdentitySnapshot.self, from: data), saved.matches(settings.contextPlan) {
                workspaceLastObservedSpaceKeys = saved.spaceKeys
            } else {
                workspaceIdentityNeedsReview = true
            }
        }
        if let data = workspacePreferences?.data(forKey: Self.rebuildBackupKey) {
            workspaceRebuildBackup = try? JSONDecoder().decode(WorkspaceRebuildBackup.self, from: data)
        }
    }

    func saveWorkspaceIdentitySnapshot() {
        guard !workspaceIsReconciling, !workspaceIdentityNeedsReview, workspaceIdentityBlockedDisplayIDs.isEmpty else { return }
        let snapshot = WorkspaceIdentitySnapshot(plan: settings.contextPlan, spaceKeys: workspaceLastObservedSpaceKeys)
        guard let preferences = workspacePreferences else { return }
        if let data = preferences.data(forKey: Self.identitySnapshotKey),
           let saved = try? JSONDecoder().decode(WorkspaceIdentitySnapshot.self, from: data), saved == snapshot { return }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        preferences.set(data, forKey: Self.identitySnapshotKey)
    }

    func rememberWorkspaceObservation(_ observation: WorkspaceLayoutObservation) {
        guard !workspaceIdentityNeedsReview else { return }
        workspaceLastObservedSpaceIDs.merge(observation.spaceIDsByDisplayID) { _, new in new }
        workspaceLastObservedSpaceKeys.merge(observation.spaceKeysByDisplayID) { _, new in new }
        saveWorkspaceIdentitySnapshot()
    }

    func workspaceIdentityUnavailable(in observation: WorkspaceLayoutObservation?) -> Set<String> {
        if settings.savedWorkspaces.initialized { return [] }
        if workspaceIdentityNeedsReview { return selectedDisplayIDs }
        guard let observation else { return [] }
        return Set(observation.displays.compactMap { display in
            guard workspaceLastObservedSpaceKeys[display.displayID] != nil,
                  observation.spaceKeysByDisplayID[display.displayID] == nil else { return nil }
            return display.displayID
        })
    }

    func prepareWorkspaceRebuild() -> WorkspaceRebuildProposal? {
        guard canAddContext, pendingContextCaptureAlignment == nil else { return nil }
        refreshWorkspaceStatus()
        guard let observation = workspaceObservation(),
              WorkspaceRebuildPolicy.contexts(existing: [], observation: observation,
                selectedDisplayIDs: selectedDisplayIDs, names: [:], defaultName: { "Desktop \($0)" }) != nil else { return nil }
        return .init(observation: observation, selectedDisplayIDs: selectedDisplayIDs,
                     configurationRevision: workspaceConfigurationRevision)
    }

    @discardableResult
    func rebuildWorkspaces(_ proposal: WorkspaceRebuildProposal) -> Bool {
        guard canAddContext, pendingContextCaptureAlignment == nil,
              selectedDisplayIDs == proposal.selectedDisplayIDs,
              workspaceConfigurationRevision == proposal.configurationRevision,
              let observation = workspaceObservation(), sameWorkspaceTopology(observation, proposal.observation) else { return false }
        let names = workspaceNameSuggestionProvider?.names(for: displayLayout,
            spaceIDsByDisplayID: observation.spaceIDsByDisplayID) ?? [:]
        guard let latest = workspaceObservation(), sameWorkspaceTopology(latest, observation),
              let contexts = WorkspaceRebuildPolicy.contexts(existing: settings.contextPlan.contexts,
                observation: latest, selectedDisplayIDs: selectedDisplayIDs,
                names: namesIncludingDesktopAliases(names, observation: latest),
                defaultName: { settings.language == .korean ? "데스크탑 \($0)" : "Desktop \($0)" }) else { return false }

        let backup = WorkspaceRebuildBackup(plan: settings.contextPlan,
            nameOrigins: workspacePreferences?.dictionary(forKey: Self.nameOriginsKey) as? [String: String] ?? workspaceNameOrigins,
            identity: WorkspaceIdentitySnapshot(plan: settings.contextPlan, spaceKeys: workspaceLastObservedSpaceKeys))
        guard let backupData = try? JSONEncoder().encode(backup) else { return false }
        workspacePreferences?.set(backupData, forKey: Self.rebuildBackupKey)
        workspaceRebuildBackup = backup
        workspaceIdentityNeedsReview = false
        workspaceIdentityBlockedDisplayIDs = []
        workspaceLastObservedSpaceKeys.merge(latest.spaceKeysByDisplayID) { _, new in new }
        workspaceLastObservedSpaceIDs.merge(latest.spaceIDsByDisplayID) { _, new in new }
        updateContextPlan { plan in
            let pinned = plan.isPinned
            plan.replaceContexts(contexts, currentContextID: contexts.first?.id ?? "")
            plan.setPinned(pinned)
        }
        let retainedIDs = Set(contexts.map(\.id))
        workspaceNameOrigins = backup.nameOrigins.filter { retainedIDs.contains($0.key) }
        for context in contexts where !Set(context.displayIDs).isDisjoint(with: selectedDisplayIDs) {
            workspaceNameOrigins[context.id] = contextUsesDesktopAlias(context) ? "" : context.name
        }
        workspacePreferences?.set(workspaceNameOrigins, forKey: Self.nameOriginsKey)
        workspaceDesktopNames = names
        workspaceDesktopNameSpaceIDs = latest.spaceIDsByDisplayID
        applyWorkspaceObservation(latest)
        saveWorkspaceIdentitySnapshot()
        return true
    }

    @discardableResult
    func restoreWorkspaceRebuildBackup() -> Bool {
        guard canAddContext, pendingContextCaptureAlignment == nil, let backup = workspaceRebuildBackup,
              let observation = workspaceObservation() else { return false }
        // Rebase surviving desktops by identity; never restore an old number onto
        // an unrelated replacement. Keep the backup if a required desktop is gone.
        for context in backup.plan.contexts {
            for (displayID, index) in context.displaySpaceIndexes where selectedDisplayIDs.contains(displayID) {
                if let previous = backup.identity.spaceKeys[displayID] {
                    guard previous.indices.contains(index),
                          observation.spaceKeysByDisplayID[displayID]?.contains(previous[index]) == true else { return false }
                }
            }
        }
        var next = settings
        var library = next.savedWorkspaces
        library.bookmarks = [:]
        library.shortcutSlots = [:]
        for context in backup.plan.contexts {
            library.assignAvailableShortcut(to: context.id)
            for (id, index) in context.displaySpaceIndexes {
                guard let keys = backup.identity.spaceKeys[id], keys.indices.contains(index) else { continue }
                library.bookmarks[context.id, default: [:]][id] = keys[index]
            }
        }
        let contexts = library.resolved(backup.plan.contexts, spaceKeys: observation.spaceKeysByDisplayID)
        next.savedWorkspaces = library
        next.contextPlan = ContextPlan(contexts: contexts, currentContextID: backup.plan.currentContextID,
                                      syncState: .needsSync, isPinned: backup.plan.isPinned)
        guard commitSavedWorkspaceChange(next, label: WorkspaceRebuildStrings(language: settings.language).restored) else { return false }
        workspaceRebuildBackup = nil
        workspacePreferences?.removeObject(forKey: Self.rebuildBackupKey)
        return true
    }

    private func sameWorkspaceTopology(_ lhs: WorkspaceLayoutObservation, _ rhs: WorkspaceLayoutObservation) -> Bool {
        lhs.spaceIDsByDisplayID == rhs.spaceIDsByDisplayID && lhs.spaceKeysByDisplayID == rhs.spaceKeysByDisplayID
            && Set(lhs.displays.map(\.displayID)) == Set(rhs.displays.map(\.displayID))
    }
}
