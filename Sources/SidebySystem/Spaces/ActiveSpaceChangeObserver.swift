import AppKit
import Foundation

public struct ActiveSpaceObservedRun: Equatable, Sendable {
    public let didPost: Bool
    public let beforeChangeCount: Int
    public let afterChangeCount: Int

    public init(didPost: Bool, beforeChangeCount: Int, afterChangeCount: Int) {
        self.didPost = didPost
        self.beforeChangeCount = beforeChangeCount
        self.afterChangeCount = afterChangeCount
    }

    public var observedChangeCount: Int {
        max(0, afterChangeCount - beforeChangeCount)
    }
}

public protocol ActiveSpaceChangeObserving: Sendable {
    func runObservingChanges(
        wait: TimeInterval,
        expectedChangeCount: Int,
        action: () -> Bool
    ) -> ActiveSpaceObservedRun
}

public struct NSWorkspaceActiveSpaceChangeObserver: ActiveSpaceChangeObserving {
    private static let pollInterval: TimeInterval = 0.05

    public init() {}

    public func runObservingChanges(
        wait: TimeInterval,
        expectedChangeCount: Int,
        action: () -> Bool
    ) -> ActiveSpaceObservedRun {
        let counter = NSWorkspaceActiveSpaceChangeCounter()
        let before = counter.changeCount
        let didPost = action()
        waitForExpectedChanges(
            counter: counter,
            beforeChangeCount: before,
            expectedChangeCount: expectedChangeCount,
            deadline: Date().addingTimeInterval(wait)
        )

        return ActiveSpaceObservedRun(
            didPost: didPost,
            beforeChangeCount: before,
            afterChangeCount: counter.changeCount
        )
    }

    // RunLoop.run(until:) returns immediately on source-less GCD worker threads,
    // so the wait must not depend on the calling thread's run loop. The counter
    // observes on the main queue; polling only needs this thread to stay off main.
    private func waitForExpectedChanges(
        counter: NSWorkspaceActiveSpaceChangeCounter,
        beforeChangeCount: Int,
        expectedChangeCount: Int,
        deadline: Date
    ) {
        let requiredChangeCount = max(1, expectedChangeCount)
        while counter.changeCount - beforeChangeCount < requiredChangeCount {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else {
                return
            }

            let step = min(Self.pollInterval, remaining)
            if Thread.isMainThread {
                if !RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(step)) {
                    Thread.sleep(forTimeInterval: step)
                }
            } else {
                Thread.sleep(forTimeInterval: step)
            }
        }
    }
}

private final class NSWorkspaceActiveSpaceChangeCounter: @unchecked Sendable {
    private var observer: NSObjectProtocol?
    private let lock = NSLock()
    private var storedChangeCount = 0

    var changeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedChangeCount
    }

    init() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.incrementChangeCount()
        }
    }

    deinit {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    private func incrementChangeCount() {
        lock.lock()
        defer { lock.unlock() }
        storedChangeCount += 1
    }
}
