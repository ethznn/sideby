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

    func testMatchingTriggerReleaseWaitsForModifierReleaseThenExecutesExactlyOnce() {
        var coordinator = ContextKeyboardCommandCoordinator()
        let command = ContextKeyboardCommand.activate(position: 2)

        XCTAssertEqual(route(.pressed(command), through: &coordinator, at: 10), .ignore)
        XCTAssertEqual(
            route(.released(command), through: &coordinator, at: 10.1),
            .waitForModifierRelease(command)
        )
        XCTAssertEqual(coordinator.gate.state, .pending(command))
        XCTAssertEqual(resume(command, through: &coordinator), .activate(contextID: "review"))
        XCTAssertEqual(resume(command, through: &coordinator), .ignore)
    }

    func testSecondCommandIsIgnoredWhilePendingExecutingAndSettling() {
        var coordinator = ContextKeyboardCommandCoordinator()

        XCTAssertEqual(route(.pressed(.move(.next)), through: &coordinator, at: 10), .ignore)
        XCTAssertEqual(route(.pressed(.move(.previous)), through: &coordinator, at: 10.1), .ignore)
        XCTAssertEqual(
            route(.released(.move(.next)), through: &coordinator, at: 10.2),
            .waitForModifierRelease(.move(.next))
        )
        XCTAssertEqual(resume(.move(.next), through: &coordinator), .move(.next))
        XCTAssertEqual(route(.pressed(.move(.previous)), through: &coordinator, at: 10.3), .ignore)

        coordinator.finishExecution(at: 11)

        XCTAssertEqual(route(.pressed(.move(.previous)), through: &coordinator, at: 11.749), .ignore)
        XCTAssertEqual(route(.pressed(.move(.previous)), through: &coordinator, at: 11.75), .ignore)
        XCTAssertEqual(
            route(.released(.move(.previous)), through: &coordinator, at: 11.76),
            .waitForModifierRelease(.move(.previous))
        )
        XCTAssertEqual(resume(.move(.previous), through: &coordinator), .move(.previous))
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
        XCTAssertEqual(route(.pressed(.move(.next)), through: &coordinator, at: 10), .ignore)
        XCTAssertEqual(
            route(.released(.move(.next)), through: &coordinator, at: 10.1),
            .waitForModifierRelease(.move(.next))
        )
        XCTAssertEqual(resume(.move(.next), through: &coordinator), .move(.next))

        coordinator.finishExecution(at: 11)
        XCTAssertEqual(
            route(.pressed(.activate(position: 10)), through: &coordinator, at: 11.75),
            .showMissingContext(position: 10)
        )
        XCTAssertEqual(route(.pressed(.move(.previous)), through: &coordinator, at: 11.75), .ignore)
        XCTAssertEqual(
            route(.released(.move(.previous)), through: &coordinator, at: 11.8),
            .waitForModifierRelease(.move(.previous))
        )
        XCTAssertEqual(resume(.move(.previous), through: &coordinator), .move(.previous))
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

    func testSecondCommandCannotReplaceCommandWaitingForModifierRelease() {
        var coordinator = ContextKeyboardCommandCoordinator(settlingDuration: 0)

        XCTAssertEqual(route(.pressed(.move(.next)), through: &coordinator, at: 10), .ignore)
        XCTAssertEqual(
            route(.released(.move(.next)), through: &coordinator, at: 10.1),
            .waitForModifierRelease(.move(.next))
        )
        XCTAssertEqual(route(.pressed(.move(.previous)), through: &coordinator, at: 10.2), .ignore)
        XCTAssertEqual(resume(.move(.previous), through: &coordinator), .ignore)
        XCTAssertEqual(resume(.move(.next), through: &coordinator), .move(.next))
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

    private func resume(
        _ command: ContextKeyboardCommand,
        through coordinator: inout ContextKeyboardCommandCoordinator
    ) -> ContextKeyboardAction {
        coordinator.resumeAfterModifierRelease(
            command,
            contextPlan: plan,
            isSidebyEnabled: true,
            isSwitching: false,
            isCapturing: false
        )
    }
}
