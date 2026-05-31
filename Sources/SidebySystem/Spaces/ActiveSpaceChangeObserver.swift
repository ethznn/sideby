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
    func runObservingChanges(wait: TimeInterval, action: () -> Bool) -> ActiveSpaceObservedRun
}

public struct NSWorkspaceActiveSpaceChangeObserver: ActiveSpaceChangeObserving {
    public init() {}

    public func runObservingChanges(wait: TimeInterval, action: () -> Bool) -> ActiveSpaceObservedRun {
        let counter = NSWorkspaceActiveSpaceChangeCounter()
        let before = counter.changeCount
        let didPost = action()
        RunLoop.current.run(until: Date().addingTimeInterval(wait))

        return ActiveSpaceObservedRun(
            didPost: didPost,
            beforeChangeCount: before,
            afterChangeCount: counter.changeCount
        )
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
