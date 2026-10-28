import Foundation

@main
struct ModelChecks {
    static func main() throws {
        let a = AnchorRecord(id: "a", displayID: "display-one", displayLabel: "Display 1")
        let b = AnchorRecord(id: "b", displayID: "display-one", displayLabel: "Display 1")
        let c = AnchorRecord(id: "c", displayID: "display-two", displayLabel: "Display 2")
        var state = ProbeState()
        state.saveWorkspace("A", anchors: [a, c])
        state.saveWorkspace("B", anchors: [b, c])
        let targets = try state.targets(for: "A")
        try state.validateSelection(targets, liveIDs: ["a", "b", "c"],
                                    connectedDisplayIDs: ["display-one", "display-two"], activeIDs: ["b", "c"])
        try rejected("anchor-not-restored") {
            try state.validateSelection(targets, liveIDs: ["c"], connectedDisplayIDs: ["display-one", "display-two"], activeIDs: ["c"])
        }
        try rejected("display-disconnected") {
            try state.validateSelection(targets, liveIDs: ["a", "c"], connectedDisplayIDs: ["display-one"], activeIDs: ["a"])
        }
        try rejected("ambiguous-anchors-on-same-space") {
            try state.validateSelection(targets, liveIDs: ["a", "b", "c"], connectedDisplayIDs: ["display-one", "display-two"], activeIDs: ["a", "b", "c"])
        }
        state.saveWorkspace("invalid", anchors: [a, b])
        try rejected("duplicate-display-target") { _ = try state.targets(for: "invalid") }
        let decoded = try JSONDecoder().decode(ProbeState.self, from: JSONEncoder().encode(state))
        let restored = try decoded.targets(for: "A")
        precondition(restored == targets)
        print("PASS: valid mixed-display target, missing restoration, disconnected display, merged anchors, duplicate display, persistence")
    }

    static func rejected(_ reason: String, _ body: () throws -> Void) throws {
        do { try body(); fatalError("Expected failure: \(reason)") }
        catch let error as ProbeFailure { precondition(error.description == reason, "Unexpected failure: \(error)") }
    }
}
