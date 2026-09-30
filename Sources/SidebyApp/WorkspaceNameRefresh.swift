import Foundation
import SidebyCore

extension SidebyAppModel {
    static var nameOriginsKey: String { "sideby.workspace-name-origins" }

    func rememberWorkspaceNameOrigin(contextID: String, automaticName: String?) {
        var origins = workspacePreferences?.dictionary(forKey: Self.nameOriginsKey) as? [String: String] ?? workspaceNameOrigins
        // Empty means explicitly named, including names that resemble a default.
        origins[contextID] = automaticName ?? ""
        let validIDs = Set(settings.contextPlan.contexts.map(\.id))
        workspaceNameOrigins = origins.filter { validIDs.contains($0.key) }
        workspacePreferences?.set(workspaceNameOrigins, forKey: Self.nameOriginsKey)
    }

    func refreshWorkspaceNames(observation: WorkspaceLayoutObservation) {
        guard !workspaceIdentityNeedsReview, workspaceIdentityUnavailable(in: observation).isEmpty,
              reconcileWorkspaceLayout(observation) else { return }
        workspaceNameRefreshCount = 0
        workspaceDesktopNames = workspaceNameSuggestionProvider?.names(for: displayLayout,
            spaceIDsByDisplayID: observation.spaceIDsByDisplayID) ?? [:]
        guard workspaceSpaceIDs() == observation.spaceIDsByDisplayID else {
            workspaceDesktopNames = [:]
            workspaceDesktopNameSpaceIDs = [:]
            return
        }
        workspaceDesktopNameSpaceIDs = observation.spaceIDsByDisplayID
        updateAutomaticWorkspaceNames()
    }

    func workspaceDesktopName(displayID: String, spaceIndex: Int) -> String? {
        desktopAlias(displayID: displayID, spaceIndex: spaceIndex) ?? workspaceDesktopNames[displayID]?[spaceIndex]
    }

    func loadWorkspaceNamesIfNeeded() {
        guard workspaceNameSuggestionProvider != nil, canAddContext, pendingContextCaptureAlignment == nil,
              let observation = workspaceObservation() else { return }
        guard workspaceDesktopNames.isEmpty || observation.displays.contains(where: {
            (workspaceDesktopNames[$0.displayID]?.count ?? 0) < $0.spaceCount
        }) else { return }
        refreshWorkspaceNames(observation: observation)
    }

    func reconcileWorkspaceDesktopNames(_ observation: WorkspaceLayoutObservation?) {
        guard let observation, workspaceDesktopNameSpaceIDs != observation.spaceIDsByDisplayID else { return }
        var names: [String: [Int: String]] = [:]
        for (displayID, ids) in observation.spaceIDsByDisplayID {
            guard let previousIDs = workspaceDesktopNameSpaceIDs[displayID] else { continue }
            for (index, id) in ids.enumerated() {
                guard let previousIndex = previousIDs.firstIndex(of: id),
                      let name = workspaceDesktopNames[displayID]?[previousIndex] else { continue }
                names[displayID, default: [:]][index] = name
            }
        }
        workspaceDesktopNames = names
        workspaceDesktopNameSpaceIDs = observation.spaceIDsByDisplayID
    }

    func updateAutomaticWorkspaceNames() {
        if settings.savedWorkspaces.initialized { return }
        let origins = workspacePreferences?.dictionary(forKey: Self.nameOriginsKey) as? [String: String] ?? workspaceNameOrigins
        for context in settings.contextPlan.contexts {
            let mayReplace: Bool
            if let original = origins[context.id] { mayReplace = !original.isEmpty && original == context.name }
            else { mayReplace = Self.isDefaultWorkspaceName(context.name) }
            guard mayReplace, let name = desktopContentName(context: context, includesAliases: false) else { continue }
            if name != context.name {
                updateContextPlan { $0.renameContext(id: context.id, name: name) }
                workspaceNameRefreshCount += 1
            }
            rememberWorkspaceNameOrigin(contextID: context.id, automaticName: name)
        }
    }

    func nameNewWorkspacesUsingDesktopAliases(previousIDs: Set<String>) {
        for context in settings.contextPlan.contexts where !previousIDs.contains(context.id) {
            guard contextUsesDesktopAlias(context),
                  let name = desktopContentName(context: context, includesAliases: true) else { continue }
            updateContextPlan { $0.renameContext(id: context.id, name: name) }
            rememberWorkspaceNameOrigin(contextID: context.id, automaticName: nil)
        }
    }

    @discardableResult
    func useDesktopContentName(contextID: String) -> Bool {
        guard canAddContext, pendingContextCaptureAlignment == nil,
              let observation = workspaceObservation() else { return false }
        // Reconcile before resolving indexes, so a reordered/deleted Space cannot supply the wrong name.
        guard refreshWorkspaceList(), let context = settings.contextPlan.contexts.first(where: { $0.id == contextID }),
              observation.spaceIDsByDisplayID == workspaceSpaceIDs(),
              let name = desktopContentName(context: context, includesAliases: true) else { return false }
        updateContextPlan { $0.renameContext(id: contextID, name: name) }
        rememberWorkspaceNameOrigin(contextID: contextID, automaticName: contextUsesDesktopAlias(context) ? nil : name)
        return true
    }

    private func desktopContentName(context: ContextDefinition, includesAliases: Bool) -> String? {
        var names: [String] = []
        let displayOrder = displayLayout.displays.map(\.id)
        let orderedIDs = context.displayIDs.sorted {
            let lhs = displayOrder.firstIndex(of: $0) ?? Int.max
            let rhs = displayOrder.firstIndex(of: $1) ?? Int.max
            return lhs == rhs ? $0 < $1 : lhs < rhs
        }
        for displayID in orderedIDs where selectedDisplayIDs.contains(displayID) {
            guard let index = context.spaceIndex(for: displayID),
                  let name = includesAliases ? workspaceDesktopName(displayID: displayID, spaceIndex: index)
                    : workspaceDesktopNames[displayID]?[index], !names.contains(name) else { continue }
            names.append(name)
        }
        return names.isEmpty ? nil : String(names.joined(separator: " / ").prefix(160))
    }

    private static func isDefaultWorkspaceName(_ name: String) -> Bool {
        name.range(of: "^(Context|Desktop|데스크탑) ?[0-9]+$", options: .regularExpression) != nil
    }

    var workspaceRefreshMessage: String {
        let copy = DailyRefreshStrings(language: settings.language)
        let count = workspaceDesktopNames.values.reduce(0) { $0 + $1.count }
        return copy.refreshResult(updatedNames: workspaceNameRefreshCount, detectedNames: count)
    }
}
