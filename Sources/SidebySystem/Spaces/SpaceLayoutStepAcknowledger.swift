import Foundation

/// Confirms a single space-switch press by polling current Space indexes
/// until the target display's index changes or the deadline passes.
/// Blocking — call off the main thread.
public struct SpaceLayoutStepAcknowledger: Sendable {
    private let pollInterval: TimeInterval

    public init(pollInterval: TimeInterval = 0.05) {
        self.pollInterval = max(pollInterval, 0.001)
    }

    public func waitForIndexChange(
        of displayID: String,
        from previousIndex: Int,
        timeout: TimeInterval,
        readIndexes: () -> [String: Int]?
    ) -> Int? {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let index = readIndexes()?[displayID], index != previousIndex {
                return index
            }
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else {
                return nil
            }
            Thread.sleep(forTimeInterval: min(pollInterval, remaining))
        }
    }
}
