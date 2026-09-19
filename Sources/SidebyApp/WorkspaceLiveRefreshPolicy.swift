import Foundation
import SidebyCore

/// Updates live desktop membership without rebuilding the user's workspace arrangement.
/// UUID keys survive process restarts; numeric handles are a session-only fallback.
enum WorkspaceLiveRefreshPolicy {
    static func contexts(existing: [ContextDefinition], observation: WorkspaceLayoutObservation,
                         selectedDisplayIDs: Set<String>, previousSpaceIDs: [String: [UInt64]],
                         previousSpaceCounts: [String: Int] = [:],
                         previousSpaceKeys: [String: [String]] = [:],
                         defaultName: (Int) -> String) -> [ContextDefinition]? {
        let displays = observation.displays
        guard !selectedDisplayIDs.isEmpty, Set(displays.map(\.displayID)) == selectedDisplayIDs,
              displays.count == selectedDisplayIDs.count,
              displays.allSatisfy({ display in
                  guard let ids = observation.spaceIDsByDisplayID[display.displayID] else { return false }
                  return display.spaceCount > 0 && ids.count == display.spaceCount && Set(ids).count == ids.count
                      && (0..<display.spaceCount).contains(display.currentSpaceIndex)
              }), displays.allSatisfy({ display in
                  guard previousSpaceKeys[display.displayID] != nil else { return true }
                  guard let keys = observation.spaceKeysByDisplayID[display.displayID] else { return false }
                  return keys.count == display.spaceCount && Set(keys).count == keys.count
              }) else { return nil }

        func identities(_ displayID: String) -> (previous: [String], current: [String])? {
            if let previous = previousSpaceKeys[displayID], let current = observation.spaceKeysByDisplayID[displayID] {
                return (previous, current)
            }
            if let previous = previousSpaceIDs[displayID], let current = observation.spaceIDsByDisplayID[displayID],
               !Set(previous).isDisjoint(with: current) {
                return (previous.map(String.init), current.map(String.init))
            }
            return nil
        }

        var result = existing.compactMap { context -> ContextDefinition? in
            var mappings = context.displaySpaceIndexes
            for display in displays {
                guard let index = mappings[display.displayID] else { continue }
                if let identity = identities(display.displayID), identity.previous.indices.contains(index) {
                    mappings[display.displayID] = identity.current.firstIndex(of: identity.previous[index])
                } else if index >= display.spaceCount {
                    mappings.removeValue(forKey: display.displayID)
                }
            }
            // Explicit empty drafts survive; a workspace whose desktops were all removed does not.
            guard !mappings.isEmpty || context.displayIDs.isEmpty else { return nil }
            return .init(id: context.id, order: context.order, name: context.name, displaySpaceIndexes: mappings)
        }

        let count = displays.map(\.spaceCount).max() ?? 0
        for index in 0..<count {
            let missing = displays.filter { display in
                guard index < display.spaceCount,
                      !result.contains(where: { $0.spaceIndex(for: display.displayID) == index }) else { return false }
                // Reassignment can intentionally leave a desktop unused. Only discover new desktops,
                // rather than recreating a workspace for every hole after each edit.
                if let identity = identities(display.displayID) {
                    return !identity.previous.contains(identity.current[index])
                }
                let knownCount = previousSpaceCounts[display.displayID]
                    ?? ((existing.compactMap { $0.spaceIndex(for: display.displayID) }.max() ?? -1) + 1)
                return existing.isEmpty || index >= knownCount
            }
            guard !missing.isEmpty else { continue }
            let missingIDs = Set(missing.map(\.displayID))
            let target = result.firstIndex { context in
                Set(context.displayIDs).isDisjoint(with: missingIDs)
                    && context.displaySpaceIndexes.contains { selectedDisplayIDs.contains($0.key) && $0.value == index }
            } ?? result.firstIndex { $0.order == index + 1 && Set($0.displayIDs).isDisjoint(with: selectedDisplayIDs) }
            var mappings = target.map { result[$0].displaySpaceIndexes } ?? [:]
            for display in missing { mappings[display.displayID] = index }
            if let target {
                let context = result[target]
                result[target] = .init(id: context.id, order: context.order, name: context.name, displaySpaceIndexes: mappings)
            } else {
                result.append(.init(id: "workspace-" + UUID().uuidString, order: (result.map(\.order).max() ?? 0) + 1,
                                    name: defaultName(index + 1), displaySpaceIndexes: mappings))
            }
        }
        return result
    }
}
