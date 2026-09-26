import Foundation
import SidebyCore

struct DesktopNameEditTarget: Identifiable {
    let id = UUID()
    let identity: DesktopNameIdentity
    let displayID: String
    let spaceIndex: Int
    let originalAlias: String?
    let automaticName: String?
    let sharedCount: Int
}

enum DesktopNameSaveResult: Equatable {
    case saved
    case invalid(DesktopNameValidation)
    case unavailable
    case conflict
}

extension SidebyAppModel {
    static var desktopAliasesKey: String { "sideby.desktop-names-v1" }

    func loadDesktopAliases() {
        guard let data = workspacePreferences?.data(forKey: Self.desktopAliasesKey),
              let names = try? JSONDecoder().decode([String: String].self, from: data) else { return }
        workspaceDesktopAliases = names.compactMapValues { value in
            guard case let .valid(name) = DesktopNameValidation.validate(value) else { return nil }
            return name
        }
    }

    func desktopAliasIdentity(displayID: String, spaceIndex: Int) -> DesktopNameIdentity? {
        guard let keys = workspaceLastObservedSpaceKeys[displayID], keys.indices.contains(spaceIndex),
              Set(keys).count == keys.count else { return nil }
        return DesktopNameIdentity(spaceKey: keys[spaceIndex], displayID: displayID)
    }

    func desktopAlias(displayID: String, spaceIndex: Int) -> String? {
        guard let identity = desktopAliasIdentity(displayID: displayID, spaceIndex: spaceIndex) else { return nil }
        return workspaceDesktopAliases[identity.storageKey]
    }

    /// Capture the cell's bookmark before reading a potentially reordered live layout.
    /// An excluded display keeps its saved assignment order until it participates again.
    func prepareDesktopNameEdit(displayID: String, spaceIndex: Int) -> DesktopNameEditTarget? {
        guard canEditWorkspaceDisplay(displayID), !workspaceIdentityNeedsReview,
              let observation = workspaceObservation(includingUnselectedDisplays: true) else { return nil }
        let identities = desktopAliasIdentities(in: observation)
        let identity: DesktopNameIdentity?
        if workspaceLastObservedSpaceKeys[displayID] != nil {
            identity = desktopAliasIdentity(displayID: displayID, spaceIndex: spaceIndex)
        } else if let previousIDs = workspaceLastObservedSpaceIDs[displayID] {
            guard previousIDs.indices.contains(spaceIndex),
                  let currentIndex = observation.spaceIDsByDisplayID[displayID]?.firstIndex(of: previousIDs[spaceIndex]) else { return nil }
            identity = identities[displayID]?[currentIndex]
        } else {
            identity = identities[displayID]?[spaceIndex]
        }
        guard let identity, let currentIndex = identities[displayID]?.first(where: { $0.value == identity })?.key else { return nil }
        if workspaceLastObservedSpaceKeys[displayID] == nil {
            // Store the identities in assignment order, including excluded displays.
            let liveIDs = observation.spaceIDsByDisplayID[displayID] ?? []
            let orderedIDs = workspaceLastObservedSpaceIDs[displayID] ?? liveIDs
            let keys = orderedIDs.compactMap { id -> String? in
                guard let index = liveIDs.firstIndex(of: id) else { return nil }
                return observation.spaceKeysByDisplayID[displayID]?[index]
            }
            guard keys.count == orderedIDs.count else { return nil }
            workspaceLastObservedSpaceKeys[displayID] = keys
            saveWorkspaceIdentitySnapshot()
        }
        let automatic = workspaceDesktopNames[displayID]?[spaceIndex]
        let count = settings.contextPlan.contexts.filter { $0.spaceIndex(for: displayID) == spaceIndex }.count
        return .init(identity: identity, displayID: displayID, spaceIndex: currentIndex,
                     originalAlias: workspaceDesktopAliases[identity.storageKey], automaticName: automatic, sharedCount: count)
    }

    @discardableResult
    func saveDesktopName(_ rawName: String?, target: DesktopNameEditTarget) -> DesktopNameSaveResult {
        let name: String?
        if let rawName {
            let validation = DesktopNameValidation.validate(rawName)
            guard case let .valid(value) = validation else { return .invalid(validation) }
            name = value
        } else { name = nil }
        guard canAddContext, pendingContextCaptureAlignment == nil,
              let observation = workspaceObservation(includingUnselectedDisplays: true),
              desktopAliasIdentities(in: observation).values.contains(where: { $0.values.contains(target.identity) })
        else { return .unavailable }
        guard workspaceDesktopAliases[target.identity.storageKey] == target.originalAlias else { return .conflict }
        var aliases = workspaceDesktopAliases
        aliases[target.identity.storageKey] = name
        guard let data = try? JSONEncoder().encode(aliases) else { return .unavailable }
        workspacePreferences?.set(data, forKey: Self.desktopAliasesKey)
        workspaceDesktopAliases = aliases
        return .saved
    }

    func desktopAliasIdentities(in observation: WorkspaceLayoutObservation) -> [String: [Int: DesktopNameIdentity]] {
        var result: [String: [Int: DesktopNameIdentity]] = [:]
        var occurrences: [DesktopNameIdentity: Int] = [:]
        for (displayID, keys) in observation.spaceKeysByDisplayID {
            guard keys.count == observation.spaceIDsByDisplayID[displayID]?.count else { continue }
            for (index, key) in keys.enumerated() {
                guard let identity = DesktopNameIdentity(spaceKey: key, displayID: displayID) else { continue }
                result[displayID, default: [:]][index] = identity
                occurrences[identity, default: 0] += 1
            }
        }
        // A duplicated identity is ambiguous, even across two different displays.
        return result.mapValues { $0.filter { occurrences[$0.value] == 1 } }
    }

    func namesIncludingDesktopAliases(_ names: [String: [Int: String]], observation: WorkspaceLayoutObservation) -> [String: [Int: String]] {
        var result = names
        for (displayID, identities) in desktopAliasIdentities(in: observation) {
            for (index, identity) in identities {
                if let name = workspaceDesktopAliases[identity.storageKey] { result[displayID, default: [:]][index] = name }
            }
        }
        return result
    }

    func contextUsesDesktopAlias(_ context: ContextDefinition) -> Bool {
        context.displaySpaceIndexes.contains { id, index in
            selectedDisplayIDs.contains(id) && desktopAlias(displayID: id, spaceIndex: index) != nil
        }
    }
}
