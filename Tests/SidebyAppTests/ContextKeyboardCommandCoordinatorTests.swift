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

    func testExecutableCommandWaitsForMatchingReleaseAndExecutesExactlyOnce() {
        var coordinator = ContextKeyboardCommandCoordinator()

        XCTAssertEqual(
            route(.pressed(.activate(position: 2)), through: &coordinator, at: 10),
            .ignore
        )
        XCTAssertEqual(
            route(.released(.activate(position: 1)), through: &coordinator, at: 10.1),
            .ignore
        )
        XCTAssertEqual(
            route(.released(.activate(position: 2)), through: &coordinator, at: 10.2),
            .activate(contextID: "review")
        )
        XCTAssertEqual(
            route(.released(.activate(position: 2)), through: &coordinator, at: 10.3),
            .ignore
        )
    }

    func testSecondCommandIsIgnoredWhilePendingExecutingAndSettling() {
        var coordinator = ContextKeyboardCommandCoordinator()

        XCTAssertEqual(route(.pressed(.move(.next)), through: &coordinator, at: 10), .ignore)
        XCTAssertEqual(route(.pressed(.move(.previous)), through: &coordinator, at: 10.1), .ignore)
        XCTAssertEqual(route(.released(.move(.next)), through: &coordinator, at: 10.2), .move(.next))
        XCTAssertEqual(route(.pressed(.move(.previous)), through: &coordinator, at: 10.3), .ignore)

        coordinator.finishExecution(at: 11)

        XCTAssertEqual(route(.pressed(.move(.previous)), through: &coordinator, at: 11.749), .ignore)
        XCTAssertEqual(route(.pressed(.move(.previous)), through: &coordinator, at: 11.75), .ignore)
        XCTAssertEqual(route(.released(.move(.previous)), through: &coordinator, at: 11.76), .move(.previous))
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
        XCTAssertEqual(route(.released(.move(.next)), through: &coordinator, at: 10.1), .move(.next))

        coordinator.finishExecution(at: 11)
        XCTAssertEqual(
            route(.pressed(.activate(position: 10)), through: &coordinator, at: 11.75),
            .showMissingContext(position: 10)
        )
        XCTAssertEqual(route(.pressed(.move(.previous)), through: &coordinator, at: 11.75), .ignore)
        XCTAssertEqual(route(.released(.move(.previous)), through: &coordinator, at: 11.8), .move(.previous))
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

    func testTriggerReleaseAllowsNextCommandWithoutModifierReleaseEvent() {
        var coordinator = ContextKeyboardCommandCoordinator(settlingDuration: 0)

        XCTAssertEqual(route(.pressed(.move(.next)), through: &coordinator, at: 10), .ignore)
        XCTAssertEqual(route(.released(.move(.next)), through: &coordinator, at: 10.1), .move(.next))
        coordinator.finishExecution(at: 10.2)
        XCTAssertEqual(route(.pressed(.move(.previous)), through: &coordinator, at: 10.2), .ignore)
        XCTAssertEqual(route(.released(.move(.previous)), through: &coordinator, at: 10.3), .move(.previous))
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
