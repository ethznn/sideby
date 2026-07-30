import XCTest
import SidebyCore
import SidebySystem
@testable import SidebyApp

final class ContextKeyboardCommandCoordinatorTests: XCTestCase {
    private let plan = ContextPlan(
        contexts: [
            ContextDefinition(id: "code", order: 1, name: "Code"),
            ContextDefinition(id: "review", order: 2, name: "Review")
        ],
        currentContextID: "code"
    )

    func testFixedPreviousNextResolveToTargetContextActivation() {
        let previousPlan = ContextPlan(
            contexts: plan.contexts,
            currentContextID: "review"
        )

        XCTAssertEqual(
            ContextKeyboardExecutionResolver.execution(
                for: .move(.next),
                contextPlan: plan
            ),
            .activate(contextID: "review")
        )
        XCTAssertEqual(
            ContextKeyboardExecutionResolver.execution(
                for: .move(.previous),
                contextPlan: previousPlan
            ),
            .activate(contextID: "code")
        )
    }

    func testFixedMoveAtBoundaryFallsBackToRelativeExecution() {
        XCTAssertEqual(
            ContextKeyboardExecutionResolver.execution(
                for: .move(.previous),
                contextPlan: plan
            ),
            .move(.previous)
        )
    }

    func testMatchingPressBeginsExecutionExactlyOnce() {
        var coordinator = ContextKeyboardCommandCoordinator()
        let command = ContextKeyboardCommand.activate(position: 2)

        XCTAssertEqual(
            route(.pressed(command), through: &coordinator, at: 10),
            .activate(contextID: "review")
        )
        XCTAssertEqual(coordinator.gate.state, .executing)
        XCTAssertEqual(
            route(.released(command), through: &coordinator, at: 10.1),
            .ignore
        )
    }

    func testSecondPressIsIgnoredWhileExecutingThenAcceptedOnCompletion() {
        var coordinator = ContextKeyboardCommandCoordinator()

        XCTAssertEqual(route(.pressed(.move(.next)), through: &coordinator, at: 10), .move(.next))
        XCTAssertEqual(route(.pressed(.move(.previous)), through: &coordinator, at: 10.1), .ignore)
        XCTAssertEqual(route(.released(.move(.next)), through: &coordinator, at: 10.2), .ignore)

        coordinator.finishExecution(at: 11)

        XCTAssertEqual(
            route(.pressed(.move(.previous)), through: &coordinator, at: 11),
            .move(.previous)
        )
    }

    func testFeedbackHappensOnPressWithoutOccupyingExecutionGate() {
        var coordinator = ContextKeyboardCommandCoordinator()

        XCTAssertEqual(
            route(
                .pressed(.move(.next)),
                through: &coordinator,
                at: 10,
                isSidebyEnabled: false
            ),
            .showSidebyOff
        )
        XCTAssertEqual(route(.pressed(.move(.next)), through: &coordinator, at: 10), .move(.next))

        coordinator.finishExecution(at: 11)
        XCTAssertEqual(
            route(.pressed(.activate(position: 10)), through: &coordinator, at: 11),
            .showMissingContext(position: 10)
        )
        XCTAssertEqual(
            route(.pressed(.move(.previous)), through: &coordinator, at: 11),
            .move(.previous)
        )
    }

    func testCaptureAndSwitchBusyPressesCannotExecuteAfterBusyEnds() {
        var coordinator = ContextKeyboardCommandCoordinator()

        XCTAssertEqual(
            route(.pressed(.move(.next)), through: &coordinator, at: 10, isSwitching: true),
            .ignore
        )
        XCTAssertEqual(route(.released(.move(.next)), through: &coordinator, at: 10.1), .ignore)
        XCTAssertEqual(
            route(.pressed(.move(.previous)), through: &coordinator, at: 11, isCapturing: true),
            .ignore
        )
        XCTAssertEqual(route(.released(.move(.previous)), through: &coordinator, at: 11.1), .ignore)
    }

    private func route(
        _ event: ContextKeyboardShortcutInputEvent,
        through coordinator: inout ContextKeyboardCommandCoordinator,
        at timestamp: Double,
        isSidebyEnabled: Bool = true,
        isSwitching: Bool = false,
        isCapturing: Bool = false
    ) -> ContextKeyboardAction {
        coordinator.handle(
            event,
            contextPlan: plan,
            isSidebyEnabled: isSidebyEnabled,
            isSwitching: isSwitching,
            isCapturing: isCapturing,
            at: timestamp
        )
    }
}
