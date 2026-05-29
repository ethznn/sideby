import Foundation
import SidebyCore

public struct AcknowledgedSpaceSwitchResult: Equatable, Sendable {
    public let command: SwitchCommand
    public let didPost: Bool
    public let expectedChangeCount: Int
    public let observedChangeCount: Int

    public init(
        command: SwitchCommand,
        didPost: Bool,
        expectedChangeCount: Int,
        observedChangeCount: Int
    ) {
        self.command = command
        self.didPost = didPost
        self.expectedChangeCount = expectedChangeCount
        self.observedChangeCount = observedChangeCount
    }

    public var didObserveAnyChange: Bool {
        observedChangeCount > 0
    }

    public var didMoveAllTargets: Bool {
        didPost && observedChangeCount >= expectedChangeCount
    }
}

public struct AcknowledgedSpaceSwitcher: Sendable {
    private let executor: any SpaceCommandExecuting
    private let targetProvider: any DisplaySwitchTargetProviding
    private let activeSpaceObserver: any ActiveSpaceChangeObserving
    private let observerWait: TimeInterval

    public init(
        executor: any SpaceCommandExecuting,
        targetProvider: any DisplaySwitchTargetProviding,
        activeSpaceObserver: any ActiveSpaceChangeObserving = NSWorkspaceActiveSpaceChangeObserver(),
        observerWait: TimeInterval = 0.85
    ) {
        self.executor = executor
        self.targetProvider = targetProvider
        self.activeSpaceObserver = activeSpaceObserver
        self.observerWait = observerWait
    }

    public func execute(_ command: SwitchCommand) -> AcknowledgedSpaceSwitchResult {
        let expectedChangeCount = max(1, targetProvider.targetPoints().count)
        let observedRun = activeSpaceObserver.runObservingChanges(wait: observerWait) {
            executor.execute(command)
        }

        return AcknowledgedSpaceSwitchResult(
            command: command,
            didPost: observedRun.didPost,
            expectedChangeCount: expectedChangeCount,
            observedChangeCount: observedRun.observedChangeCount
        )
    }
}
