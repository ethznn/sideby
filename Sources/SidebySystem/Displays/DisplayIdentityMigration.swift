import SidebyCore

/// Migrates only identities supported by a unique current display snapshot.
/// Absent displays and ambiguous legacy identities remain available for review.
public enum DisplayIdentityMigration {
    @discardableResult
    public static func migrate(
        settings: inout AppSettings,
        snapshots: [DisplaySnapshot]
    ) -> [String: String] {
        let storedIDs = Set(settings.contextPlan.contexts.flatMap(\.displayIDs))
            .union(settings.displayRowOrder)
            .union(settings.displaySelection.selectedDisplayIDs)
            .union(settings.displaySelection.knownDisplayNames.keys)
        let legacyIdentities = storedIDs.compactMap { id in
            LegacyIdentity(id: id).map { (id, $0) }
        }
        var candidates: [String: String] = [:]

        for (oldID, identity) in legacyIdentities {
            let exactMatches = snapshots.filter { DisplayLayoutMapper.legacyID(for: $0) == oldID }
            let snapshot: DisplaySnapshot
            if exactMatches.count == 1, let exact = exactMatches.first {
                snapshot = exact
            } else {
                guard exactMatches.isEmpty, identity.serial != 0,
                      legacyIdentities.filter({ $0.1.hardwareKey == identity.hardwareKey }).count == 1
                else { continue }
                let serialMatches = snapshots.filter {
                    $0.vendorNumber == identity.vendor && $0.modelNumber == identity.model && $0.serialNumber == identity.serial
                }
                guard serialMatches.count == 1, let serialMatch = serialMatches.first else { continue }
                snapshot = serialMatch
            }

            let newID = DisplayLayoutMapper.stableID(for: snapshot)
            guard newID.hasPrefix("uuid:"), !storedIDs.contains(newID),
                  snapshots.filter({ DisplayLayoutMapper.stableID(for: $0) == newID }).count == 1
            else { continue }
            candidates[oldID] = newID
        }

        // Do not merge separate stored identities into a single current display.
        let destinationCounts = Dictionary(grouping: candidates.values, by: { $0 }).mapValues(\.count)
        let mapping = candidates.filter { destinationCounts[$0.value] == 1 }
        guard !mapping.isEmpty else { return [:] }

        let oldPlan = settings.contextPlan
        settings.contextPlan = ContextPlan(
            contexts: oldPlan.contexts.map { context in
                ContextDefinition(
                    id: context.id,
                    order: context.order,
                    name: context.name,
                    displaySpaceIndexes: Dictionary(uniqueKeysWithValues: context.displaySpaceIndexes.map { id, index in
                        (mapping[id] ?? id, index)
                    })
                )
            },
            currentContextID: oldPlan.currentContextID,
            syncState: oldPlan.syncState,
            isPinned: oldPlan.isPinned
        )
        settings.displayRowOrder = settings.displayRowOrder.map { mapping[$0] ?? $0 }
        let oldSelection = settings.displaySelection
        settings.displaySelection = DisplaySelection(
            hasInitialized: oldSelection.hasInitialized,
            selectedDisplayIDs: Set(oldSelection.selectedDisplayIDs.map { mapping[$0] ?? $0 }),
            knownDisplayNames: Dictionary(uniqueKeysWithValues: oldSelection.knownDisplayNames.map { id, name in
                (mapping[id] ?? id, name)
            })
        )
        return mapping
    }

    private struct LegacyIdentity {
        let vendor: UInt32
        let model: UInt32
        let serial: UInt32

        var hardwareKey: String { "\(vendor)-\(model)-\(serial)" }

        init?(id: String) {
            let parts = id.split(separator: "-", omittingEmptySubsequences: false)
            guard parts.count == 4 else { return nil }
            let numbers = parts.compactMap { UInt32($0) }
            guard numbers.count == 4, numbers.map(String.init).joined(separator: "-") == id else { return nil }
            vendor = numbers[0]
            model = numbers[1]
            serial = numbers[2]
        }
    }
}
