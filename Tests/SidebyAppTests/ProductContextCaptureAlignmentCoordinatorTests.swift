import XCTest
import SidebyCore
@testable import SidebyApp

final class ProductContextCaptureAlignmentCoordinatorTests: XCTestCase {
    private let requestID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let otherRequestID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let candidates = [
        ContextCaptureAlignmentCandidate(id: "context-1", order: 1, name: "One"),
        ContextCaptureAlignmentCandidate(id: "context-2", order: 2, name: "Two")
    ]

    func testChooseTransitionsToSelectedCandidateActivation() {
        var coordinator = ProductContextCaptureAlignmentCoordinator()
        let request = ProductContextCaptureAlignmentRequest(id: requestID, candidates: candidates)

        coordinator.present(candidates: candidates, requestID: requestID)

        XCTAssertEqual(coordinator.state, .choosing(request))
        XCTAssertEqual(
            coordinator.choose(contextID: "context-2"),
            .activate(contextID: "context-2", requestID: request.id)
        )
        XCTAssertEqual(
            coordinator.state,
            .transitioning(requestID: request.id, contextID: "context-2")
        )
    }

    func testCancelReturnsChoosingStateToIdleWithoutActivation() {
        var coordinator = ProductContextCaptureAlignmentCoordinator()

        coordinator.present(candidates: candidates, requestID: requestID)
        coordinator.cancel()

        XCTAssertEqual(coordinator.state, .idle)
    }

    func testChooseRejectsCandidateOutsideRequestAndPreservesChooser() {
        var coordinator = ProductContextCaptureAlignmentCoordinator()
        let request = ProductContextCaptureAlignmentRequest(id: requestID, candidates: candidates)

        coordinator.present(candidates: candidates, requestID: requestID)

        XCTAssertEqual(coordinator.choose(contextID: "missing"), .none)
        XCTAssertEqual(coordinator.state, .choosing(request))
    }

    func testFinishOnlyDismissesTransitionForMatchingRequest() {
        var coordinator = ProductContextCaptureAlignmentCoordinator()

        coordinator.present(candidates: candidates, requestID: requestID)
        _ = coordinator.choose(contextID: "context-2")
        coordinator.finish(requestID: otherRequestID)

        XCTAssertEqual(
            coordinator.state,
            .transitioning(requestID: requestID, contextID: "context-2")
        )

        coordinator.finish(requestID: requestID)

        XCTAssertEqual(coordinator.state, .idle)
    }
}
