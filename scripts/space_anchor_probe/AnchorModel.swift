import Foundation

struct AnchorRecord: Codable, Equatable {
    let id: String
    let displayID: String
    let displayLabel: String
}

struct WorkspaceRecord: Codable, Equatable {
    let name: String
    let anchorIDs: [String]
}

struct ProbeState: Codable {
    var version = 1
    var anchors: [AnchorRecord] = []
    var workspaces: [WorkspaceRecord] = []

    func targets(for name: String) throws -> [AnchorRecord] {
        guard let workspace = workspaces.first(where: { $0.name == name }),
              !workspace.anchorIDs.isEmpty else { throw ProbeFailure("workspace-not-captured") }
        guard Set(workspace.anchorIDs).count == workspace.anchorIDs.count else {
            throw ProbeFailure("duplicate-anchor-reference")
        }
        let targets = try workspace.anchorIDs.map { id in
            let matches = anchors.filter { $0.id == id }
            guard matches.count == 1 else { throw ProbeFailure("missing-or-duplicate-anchor-record") }
            return matches[0]
        }
        guard Set(targets.map(\.displayID)).count == targets.count else {
            throw ProbeFailure("duplicate-display-target")
        }
        return targets
    }

    func validateSelection(_ targets: [AnchorRecord], liveIDs: Set<String>,
                           connectedDisplayIDs: Set<String>, activeIDs: Set<String>) throws {
        for target in targets {
            guard connectedDisplayIDs.contains(target.displayID) else { throw ProbeFailure("display-disconnected") }
            guard liveIDs.contains(target.id) else { throw ProbeFailure("anchor-not-restored") }
            let active = anchors.filter { $0.displayID == target.displayID && activeIDs.contains($0.id) }
            guard active.count <= 1 else { throw ProbeFailure("ambiguous-anchors-on-same-space") }
        }
    }

    mutating func saveWorkspace(_ name: String, anchors records: [AnchorRecord]) {
        for record in records where !anchors.contains(where: { $0.id == record.id }) { anchors.append(record) }
        workspaces.removeAll { $0.name == name }
        workspaces.append(WorkspaceRecord(name: name, anchorIDs: records.map(\.id)))
    }
}

struct ProbeFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
