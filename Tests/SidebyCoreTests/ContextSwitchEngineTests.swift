import XCTest
@testable import SidebyCore

final class ContextSwitchEngineTests: XCTestCase {
    func testExecutesAllowedCommandThroughExecutor() {
        let executor = RecordingSpaceExecutor()
        let engine = ContextSwitchEngine(executor: executor)

        let result = engine.switchContext(
            .next,
            mode: .shortcut,
            inputMethod: .shortcut,
            runtimeState: .dualDisplay
        )

        XCTAssertTrue(result.didExecute)
        XCTAssertEqual(result.command, .next)
        XCTAssertEqual(executor.commands, [.next])
    }

    func testDoesNotExecuteBlockedCommand() {
        let executor = RecordingSpaceExecutor()
        let engine = ContextSwitchEngine(executor: executor)
        var state = RuntimeState.dualDisplay
        state.availableSpaceCount = 1

        let result = engine.switchContext(
            .next,
            mode: .shortcut,
            inputMethod: .shortcut,
            runtimeState: state
        )

        XCTAssertFalse(result.didExecute)
        XCTAssertTrue(executor.commands.isEmpty)
        XCTAssertEqual(result.diagnostics.first?.title, "Only one Space is available")
    }
}

private final class RecordingSpaceExecutor: SpaceCommandExecuting, @unchecked Sendable {
    private(set) var commands: [SwitchCommand] = []

    func execute(_ command: SwitchCommand) -> Bool {
        commands.append(command)
        return true
    }
}

extension RuntimeState {
    static let dualDisplay = RuntimeState(
        accessibilityPermission: .granted,
        displayLayout: DisplayLayout(
            displays: [
                DisplayInfo(id: "built-in", name: "Built-in Display", isPrimary: true, isBuiltin: true),
                DisplayInfo(id: "external-lg", name: "LG Display", isPrimary: false, isBuiltin: false)
            ]
        ),
        availableSpaceCount: 3
    )
}
