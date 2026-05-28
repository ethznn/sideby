public enum ContextCapturePhase: Equatable, Sendable {
    case aligning(attempt: Int)
    case capturing(order: Int)
    case completed(currentContextID: String)
    case failed(reason: String)
    case stopped
}

public struct ContextCaptureDraft: Equatable, Sendable {
    public let id: String
    public let order: Int
    public let name: String

    public init(order: Int, name: String) {
        self.id = "context-\(max(order, 1))"
        self.order = max(order, 1)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = trimmed.isEmpty ? "Context \(max(order, 1))" : trimmed
    }

    public var contextDefinition: ContextDefinition {
        ContextDefinition(id: id, order: order, name: name)
    }
}

public struct ContextCaptureSession: Equatable, Sendable {
    public let captureLimit: Int
    public let maxAlignmentAttempts: Int
    public private(set) var phase: ContextCapturePhase
    public private(set) var draftContexts: [ContextCaptureDraft]

    public init(captureLimit: Int, maxAlignmentAttempts: Int = 12) {
        self.init(
            captureLimit: captureLimit,
            maxAlignmentAttempts: maxAlignmentAttempts,
            phase: .aligning(attempt: 1),
            draftContexts: []
        )
    }

    init(
        captureLimit: Int,
        maxAlignmentAttempts: Int = 12,
        phase: ContextCapturePhase,
        draftContexts: [ContextCaptureDraft]
    ) {
        self.captureLimit = min(max(captureLimit, 1), 12)
        self.maxAlignmentAttempts = min(max(maxAlignmentAttempts, 1), 24)
        self.phase = phase
        self.draftContexts = draftContexts.sorted { $0.order < $1.order }
    }

    public var shouldCommitDrafts: Bool {
        if case .completed = phase {
            return true
        }
        return false
    }

    public var currentCaptureOrder: Int? {
        guard case .capturing(let order) = phase else {
            return nil
        }
        return order
    }

    public var completedContextDefinitions: [ContextDefinition]? {
        guard case .completed(let currentContextID) = phase else {
            return nil
        }

        let sortedDrafts = draftContexts.sorted { $0.order < $1.order }
        guard
            let completedOrder = completedOrder(for: currentContextID, in: sortedDrafts),
            completedOrder >= 1
        else {
            return nil
        }

        let completedDrafts = sortedDrafts.filter { $0.order <= completedOrder }
        let expectedOrders = Array(1...completedOrder)
        guard completedDrafts.map(\.order) == expectedOrders else {
            return nil
        }

        guard completedDrafts.last?.id == currentContextID else {
            return nil
        }

        return completedDrafts.map(\.contextDefinition)
    }

    private var isTerminal: Bool {
        switch phase {
        case .completed, .failed, .stopped:
            return true
        case .aligning, .capturing:
            return false
        }
    }

    private func completedOrder(for currentContextID: String, in drafts: [ContextCaptureDraft]) -> Int? {
        if let matchingDraft = drafts.first(where: { $0.id == currentContextID }) {
            return matchingDraft.order
        }

        let prefix = "context-"
        guard currentContextID.hasPrefix(prefix) else {
            return nil
        }

        return Int(currentContextID.dropFirst(prefix.count))
    }

    public mutating func recordAlignment(previousDidChange: Bool) {
        guard case .aligning(let attempt) = phase else {
            return
        }

        if previousDidChange {
            if attempt < maxAlignmentAttempts {
                phase = .aligning(attempt: attempt + 1)
            } else {
                phase = .failed(reason: "Could not align to first Space")
            }
        } else {
            phase = .capturing(order: 1)
        }
    }

    public mutating func recordCurrentSpace(name: String) {
        guard case .capturing(let order) = phase else {
            return
        }

        let draft = ContextCaptureDraft(order: order, name: name)
        if let index = draftContexts.firstIndex(where: { $0.order == order }) {
            draftContexts[index] = draft
        } else {
            draftContexts.append(draft)
        }
        draftContexts.sort { $0.order < $1.order }
    }

    public mutating func recordForwardSwitch(didMoveAllTargets: Bool) {
        guard case .capturing(let order) = phase else {
            return
        }

        guard draftContexts.contains(where: { $0.order == order }) else {
            phase = .failed(reason: "Missing captured Context")
            return
        }

        if order >= captureLimit || !didMoveAllTargets {
            phase = .completed(currentContextID: "context-\(order)")
        } else {
            phase = .capturing(order: order + 1)
        }
    }

    public mutating func fail(reason: String) {
        guard !isTerminal else {
            return
        }
        phase = .failed(reason: reason)
    }

    public mutating func stop() {
        guard !isTerminal else {
            return
        }
        phase = .stopped
    }
}
