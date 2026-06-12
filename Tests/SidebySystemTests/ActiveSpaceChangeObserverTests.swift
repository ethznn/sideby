import AppKit
import XCTest
@testable import SidebySystem

final class ActiveSpaceChangeObserverTests: XCTestCase {
    func testRunObservingChangesWaitsForObservationWindowOffMainThread() {
        let observer = NSWorkspaceActiveSpaceChangeObserver()
        let measurement = ObserverRunMeasurement()
        let finished = expectation(description: "observer run finished")

        DispatchQueue.global(qos: .userInitiated).async {
            let start = Date()
            let run = observer.runObservingChanges(wait: 0.4, expectedChangeCount: 1) { true }
            measurement.record(run: run, elapsed: Date().timeIntervalSince(start))
            finished.fulfill()
        }

        wait(for: [finished], timeout: 3.0)
        XCTAssertGreaterThanOrEqual(measurement.elapsed, 0.35)
    }

    func testRunObservingChangesReturnsEarlyOnceExpectedChangeCountObserved() {
        let observer = NSWorkspaceActiveSpaceChangeObserver()
        let measurement = ObserverRunMeasurement()
        let finished = expectation(description: "observer run finished")

        DispatchQueue.global(qos: .userInitiated).async {
            let start = Date()
            let run = observer.runObservingChanges(wait: 5.0, expectedChangeCount: 1) { true }
            measurement.record(run: run, elapsed: Date().timeIntervalSince(start))
            finished.fulfill()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSWorkspace.shared.notificationCenter.post(
                name: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil
            )
        }

        wait(for: [finished], timeout: 4.0)
        XCTAssertGreaterThanOrEqual(measurement.run?.observedChangeCount ?? 0, 1)
        XCTAssertLessThan(measurement.elapsed, 2.0)
    }
}

private final class ObserverRunMeasurement: @unchecked Sendable {
    private let lock = NSLock()
    private var storedRun: ActiveSpaceObservedRun?
    private var storedElapsed: TimeInterval = 0

    var run: ActiveSpaceObservedRun? {
        lock.lock()
        defer { lock.unlock() }
        return storedRun
    }

    var elapsed: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return storedElapsed
    }

    func record(run: ActiveSpaceObservedRun, elapsed: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        storedRun = run
        storedElapsed = elapsed
    }
}
