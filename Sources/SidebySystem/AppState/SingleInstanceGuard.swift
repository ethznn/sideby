import AppKit
import Foundation

public struct RunningApplicationSnapshot: Equatable, Sendable {
    public let processIdentifier: Int32
    public let bundleIdentifier: String

    public init(processIdentifier: Int32, bundleIdentifier: String) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
    }
}

public enum SingleInstanceStartupDecision: Equatable, Sendable {
    case continueLaunch
    case activateExisting(RunningApplicationSnapshot)
}

public struct SingleInstanceGuard: Sendable {
    private let currentProcessIdentifier: Int32
    private let bundleIdentifier: String?
    private let runningApplications: [RunningApplicationSnapshot]

    public init(
        currentProcessIdentifier: Int32 = ProcessInfo.processInfo.processIdentifier,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        runningApplications: [RunningApplicationSnapshot]? = nil
    ) {
        self.currentProcessIdentifier = currentProcessIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.runningApplications = runningApplications ?? Self.runningApplicationSnapshots()
    }

    public func startupDecision() -> SingleInstanceStartupDecision {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else {
            return .continueLaunch
        }

        guard let existingApplication = runningApplications.first(where: { application in
            application.bundleIdentifier == bundleIdentifier
                && application.processIdentifier != currentProcessIdentifier
        }) else {
            return .continueLaunch
        }

        return .activateExisting(existingApplication)
    }

    @MainActor
    public static func activateExistingApplicationAndReturnShouldTerminate(
        currentProcessIdentifier: Int32 = ProcessInfo.processInfo.processIdentifier,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) -> Bool {
        let guarder = SingleInstanceGuard(
            currentProcessIdentifier: currentProcessIdentifier,
            bundleIdentifier: bundleIdentifier,
            runningApplications: runningApplicationSnapshots()
        )

        switch guarder.startupDecision() {
        case .continueLaunch:
            return false
        case .activateExisting(let existingApplication):
            activateApplication(processIdentifier: existingApplication.processIdentifier)
            return true
        }
    }

    private static func runningApplicationSnapshots() -> [RunningApplicationSnapshot] {
        NSWorkspace.shared.runningApplications.compactMap { application in
            guard let bundleIdentifier = application.bundleIdentifier else {
                return nil
            }

            return RunningApplicationSnapshot(
                processIdentifier: application.processIdentifier,
                bundleIdentifier: bundleIdentifier
            )
        }
    }

    @MainActor
    private static func activateApplication(processIdentifier: Int32) {
        guard let application = NSWorkspace.shared.runningApplications.first(where: { application in
            application.processIdentifier == processIdentifier
        }) else {
            return
        }

        application.activate(options: [.activateAllWindows])
    }
}
