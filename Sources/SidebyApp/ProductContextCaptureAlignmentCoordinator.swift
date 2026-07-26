import Foundation
import SidebyCore

struct ProductContextCaptureAlignmentRequest: Equatable, Identifiable {
    let id: UUID
    let candidates: [ContextCaptureAlignmentCandidate]
}

enum ProductContextCaptureAlignmentState: Equatable {
    case idle
    case choosing(ProductContextCaptureAlignmentRequest)
    case transitioning(requestID: UUID, contextID: String)
}

enum ProductContextCaptureAlignmentAction: Equatable {
    case none
    case activate(contextID: String, requestID: UUID)
}

struct ProductContextCaptureAlignmentCoordinator: Equatable {
    private(set) var state: ProductContextCaptureAlignmentState

    init(state: ProductContextCaptureAlignmentState = .idle) {
        self.state = state
    }

    mutating func present(candidates: [ContextCaptureAlignmentCandidate], requestID: UUID) {
        guard !candidates.isEmpty else {
            state = .idle
            return
        }

        state = .choosing(.init(id: requestID, candidates: candidates))
    }

    mutating func choose(contextID: String) -> ProductContextCaptureAlignmentAction {
        guard case let .choosing(request) = state,
              request.candidates.contains(where: { $0.id == contextID })
        else {
            return .none
        }

        state = .transitioning(requestID: request.id, contextID: contextID)
        return .activate(contextID: contextID, requestID: request.id)
    }

    mutating func cancel() {
        state = .idle
    }

    mutating func finish(requestID: UUID) {
        guard case let .transitioning(activeRequestID, _) = state,
              activeRequestID == requestID
        else {
            return
        }

        state = .idle
    }

    mutating func invalidate() {
        state = .idle
    }
}
