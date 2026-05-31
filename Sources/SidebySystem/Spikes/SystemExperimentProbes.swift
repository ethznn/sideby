import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import SidebyCore

public struct AXFocusAnchorResult: Equatable, Sendable {
    public let point: CGPoint
    public let lookupErrorCode: Int32
    public let raiseErrorCode: Int32?
    public let processIdentifier: pid_t?
    public let frontmostProcessIdentifierBeforeRaise: pid_t?
    public let frontmostProcessIdentifierAfterRaise: pid_t?
    public let role: String?
    public let title: String?

    public init(
        point: CGPoint,
        lookupErrorCode: Int32,
        raiseErrorCode: Int32?,
        processIdentifier: pid_t?,
        frontmostProcessIdentifierBeforeRaise: pid_t? = nil,
        frontmostProcessIdentifierAfterRaise: pid_t? = nil,
        role: String?,
        title: String?
    ) {
        self.point = point
        self.lookupErrorCode = lookupErrorCode
        self.raiseErrorCode = raiseErrorCode
        self.processIdentifier = processIdentifier
        self.frontmostProcessIdentifierBeforeRaise = frontmostProcessIdentifierBeforeRaise
        self.frontmostProcessIdentifierAfterRaise = frontmostProcessIdentifierAfterRaise
        self.role = role
        self.title = title
    }

    public var summary: String {
        let lookup = "lookup=\(lookupErrorCode)"
        let raise = raiseErrorCode.map { "raise=\($0)" } ?? "raise=skipped"
        let pid = processIdentifier.map { "pid=\($0)" } ?? "pid=unknown"
        let frontmostBefore = frontmostProcessIdentifierBeforeRaise.map(String.init) ?? "unknown"
        let frontmostAfter = frontmostProcessIdentifierAfterRaise.map(String.init) ?? "unknown"
        let role = role ?? "role=unknown"
        let title = title?.isEmpty == false ? title! : "untitled"
        return "\(lookup), \(raise), \(pid), frontmost \(frontmostBefore)->\(frontmostAfter), \(role), \(title)"
    }
}

public protocol AXFocusAnchorProbing: Sendable {
    func probe(point: CGPoint, performRaise: Bool) -> AXFocusAnchorResult
}

public struct AXFocusAnchorProbe: AXFocusAnchorProbing {
    private let targetProvider: any DisplaySwitchTargetProviding

    public init(targetProvider: any DisplaySwitchTargetProviding = CGDisplaySwitchTargetProvider()) {
        self.targetProvider = targetProvider
    }

    public func probeTargets(performRaise: Bool) -> [AXFocusAnchorResult] {
        targetProvider.targetPoints().map { probe(point: $0, performRaise: performRaise) }
    }

    public func probe(point: CGPoint, performRaise: Bool) -> AXFocusAnchorResult {
        let frontmostBeforeRaise = NSWorkspace.shared.frontmostApplication?.processIdentifier
        var element: AXUIElement?
        let lookupError = AXUIElementCopyElementAtPosition(
            AXUIElementCreateSystemWide(),
            Float(point.x),
            Float(point.y),
            &element
        )

        guard let element else {
            return AXFocusAnchorResult(
                point: point,
                lookupErrorCode: lookupError.rawValue,
                raiseErrorCode: nil,
                processIdentifier: nil,
                frontmostProcessIdentifierBeforeRaise: frontmostBeforeRaise,
                frontmostProcessIdentifierAfterRaise: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                role: nil,
                title: nil
            )
        }

        var processIdentifier: pid_t = 0
        let pid = AXUIElementGetPid(element, &processIdentifier) == .success ? processIdentifier : nil
        let actionTarget = windowElement(for: element) ?? element
        let raiseError = performRaise ? AXUIElementPerformAction(actionTarget, kAXRaiseAction as CFString) : nil
        let frontmostAfterRaise = NSWorkspace.shared.frontmostApplication?.processIdentifier

        return AXFocusAnchorResult(
            point: point,
            lookupErrorCode: lookupError.rawValue,
            raiseErrorCode: raiseError?.rawValue,
            processIdentifier: pid,
            frontmostProcessIdentifierBeforeRaise: frontmostBeforeRaise,
            frontmostProcessIdentifierAfterRaise: frontmostAfterRaise,
            role: stringAttribute(kAXRoleAttribute, from: element),
            title: stringAttribute(kAXTitleAttribute, from: element)
        )
    }

    private func windowElement(for element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &value) == .success else {
            return nil
        }

        let window = value as! AXUIElement
        return window
    }

    private func stringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }

        return value as? String
    }
}

public struct AXFocusAnchorDisplaySpaceCommandExecutor: SpaceCommandExecuting {
    private let baseExecutor: any SpaceCommandExecuting
    private let targetProvider: any DisplaySwitchTargetProviding
    private let anchorProbe: any AXFocusAnchorProbing
    private let focusDelay: TimeInterval
    private let switchDelay: TimeInterval

    public init(
        baseExecutor: any SpaceCommandExecuting = MacSpaceCommandExecutor(poster: AppleScriptKeyEventPoster()),
        targetProvider: any DisplaySwitchTargetProviding = CGDisplaySwitchTargetProvider(),
        anchorProbe: any AXFocusAnchorProbing = AXFocusAnchorProbe(),
        focusDelay: TimeInterval = 0.04,
        switchDelay: TimeInterval = 0.32
    ) {
        self.baseExecutor = baseExecutor
        self.targetProvider = targetProvider
        self.anchorProbe = anchorProbe
        self.focusDelay = focusDelay
        self.switchDelay = switchDelay
    }

    public func execute(_ command: SwitchCommand) -> Bool {
        let points = targetProvider.targetPoints()
        guard !points.isEmpty else {
            return false
        }

        var didExecuteAll = true
        for point in points {
            let result = anchorProbe.probe(point: point, performRaise: true)
            didExecuteAll = result.lookupErrorCode == AXError.success.rawValue && didExecuteAll
            Thread.sleep(forTimeInterval: focusDelay)
            didExecuteAll = baseExecutor.execute(command) && didExecuteAll
            Thread.sleep(forTimeInterval: switchDelay)
        }

        return didExecuteAll
    }
}

public protocol DisplayTargetClicking: Sendable {
    func click(point: CGPoint) -> Bool
    func cleanup()
}

public struct OverlayClickDisplaySpaceCommandExecutor: SpaceCommandExecuting {
    private let baseExecutor: any SpaceCommandExecuting
    private let targetProvider: any DisplaySwitchTargetProviding
    private let clicker: any DisplayTargetClicking
    private let postEventAccessChecker: any PostEventAccessChecking
    private let clickDelay: TimeInterval
    private let switchDelay: TimeInterval

    public init(
        baseExecutor: any SpaceCommandExecuting = MacSpaceCommandExecutor(poster: AppleScriptKeyEventPoster()),
        targetProvider: any DisplaySwitchTargetProviding = CGDisplaySwitchTargetProvider(),
        clicker: any DisplayTargetClicking = AppKitOverlayDisplayTargetClicker(),
        postEventAccessChecker: any PostEventAccessChecking = CGPostEventAccessChecker(),
        clickDelay: TimeInterval = 0.05,
        switchDelay: TimeInterval = HiddenSwitchTimingConfiguration.optimizedCandidate.switchDelay
    ) {
        self.baseExecutor = baseExecutor
        self.targetProvider = targetProvider
        self.clicker = clicker
        self.postEventAccessChecker = postEventAccessChecker
        self.clickDelay = clickDelay
        self.switchDelay = switchDelay
    }

    public func execute(_ command: SwitchCommand) -> Bool {
        guard postEventAccessChecker.hasOrRequestAccess() else {
            return false
        }

        let points = targetProvider.targetPoints()
        guard !points.isEmpty else {
            return false
        }

        var didExecuteAll = true
        for point in points {
            didExecuteAll = clicker.click(point: point) && didExecuteAll
            Thread.sleep(forTimeInterval: clickDelay)
            didExecuteAll = baseExecutor.execute(command) && didExecuteAll
            Thread.sleep(forTimeInterval: switchDelay)
        }

        clicker.cleanup()
        return didExecuteAll
    }
}

public final class AppKitOverlayDisplayTargetClicker: DisplayTargetClicking, @unchecked Sendable {
    private let size: CGFloat
    private let alpha: CGFloat
    private var panels: [NSPanel] = []

    public init(size: CGFloat = 24, alpha: CGFloat = 0.02) {
        self.size = size
        self.alpha = alpha
    }

    public func click(point: CGPoint) -> Bool {
        runOnMain { [self] in
            let center = self.appKitCenter(for: point)
            let panel = FocusOverlayPanel(
                contentRect: CGRect(
                    x: center.x - self.size / 2,
                    y: center.y - self.size / 2,
                    width: self.size,
                    height: self.size
                ),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            panel.backgroundColor = NSColor.black.withAlphaComponent(self.alpha)
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            panel.hasShadow = false
            panel.ignoresMouseEvents = false
            panel.isOpaque = false
            panel.isReleasedWhenClosed = false
            panel.level = .floating
            panel.orderFrontRegardless()
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            self.panels.append(panel)
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        }

        return postClick(at: point)
    }

    public func cleanup() {
        runOnMain { [self] in
            self.panels.forEach { $0.close() }
            self.panels.removeAll()
        }
    }

    private func postClick(at point: CGPoint) -> Bool {
        guard
            let down = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseDown,
                mouseCursorPosition: point,
                mouseButton: .left
            ),
            let up = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseUp,
                mouseCursorPosition: point,
                mouseButton: .left
            )
        else {
            return false
        }

        down.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.02)
        up.post(tap: .cghidEventTap)
        return true
    }

    @MainActor private func appKitCenter(for point: CGPoint) -> CGPoint {
        let displayID = displayID(containing: point)
        let screen = NSScreen.screens.first { screen in
            guard let screenDisplayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }

            return screenDisplayID.uint32Value == displayID
        }

        guard let screen else {
            return point
        }

        return CGPoint(x: screen.frame.midX, y: screen.frame.midY)
    }

    private func displayID(containing point: CGPoint) -> CGDirectDisplayID {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return CGMainDisplayID()
        }

        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displayIDs, &count) == .success else {
            return CGMainDisplayID()
        }

        return displayIDs.first { CGDisplayBounds($0).contains(point) } ?? CGMainDisplayID()
    }

    private func runOnMain(_ action: @MainActor @escaping () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                action()
            }
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    action()
                }
            }
        }
    }
}

private final class FocusOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull && !isEmpty else {
            return 0
        }

        return width * height
    }
}

public struct AppleScriptExecutionResult: Equatable, Sendable {
    public let didExecute: Bool
    public let output: String?
    public let errorMessage: String?

    public init(didExecute: Bool, output: String?, errorMessage: String?) {
        self.didExecute = didExecute
        self.output = output
        self.errorMessage = errorMessage
    }

    public var summary: String {
        if didExecute {
            return output?.isEmpty == false ? "Executed: \(output!)" : "Executed"
        }

        return errorMessage.map { "Failed: \($0)" } ?? "Failed"
    }
}

public protocol AppleScriptExecuting: Sendable {
    func execute(source: String) -> AppleScriptExecutionResult
}

public struct NSAppleScriptExecutor: AppleScriptExecuting {
    public init() {}

    public func execute(source: String) -> AppleScriptExecutionResult {
        guard let script = NSAppleScript(source: source) else {
            return AppleScriptExecutionResult(
                didExecute: false,
                output: nil,
                errorMessage: "Could not compile AppleScript source"
            )
        }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            return AppleScriptExecutionResult(
                didExecute: false,
                output: nil,
                errorMessage: error.description
            )
        }

        return AppleScriptExecutionResult(
            didExecute: true,
            output: result.stringValue,
            errorMessage: nil
        )
    }
}

public struct ShortcutsBridgeProbe<Executor: AppleScriptExecuting>: Sendable {
    private let executor: Executor

    public init(executor: Executor) {
        self.executor = executor
    }

    public func runShortcut(named name: String) -> AppleScriptExecutionResult {
        executor.execute(source: Self.script(shortcutName: name))
    }

    public static func script(shortcutName: String) -> String {
        """
        tell application "Shortcuts Events"
            run shortcut \(quotedAppleScriptString(shortcutName))
        end tell
        """
    }

    private static func quotedAppleScriptString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

public extension ShortcutsBridgeProbe where Executor == NSAppleScriptExecutor {
    init() {
        self.init(executor: NSAppleScriptExecutor())
    }
}

public struct ProcessExecutionResult: Equatable, Sendable {
    public let exitCode: Int32
    public let output: String
    public let errorOutput: String

    public init(exitCode: Int32, output: String, errorOutput: String) {
        self.exitCode = exitCode
        self.output = output
        self.errorOutput = errorOutput
    }

    public var didSucceed: Bool {
        exitCode == 0
    }

    public var summary: String {
        let detail = didSucceed ? output : errorOutput
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "exit \(exitCode)" : "exit \(exitCode): \(trimmed)"
    }
}

public protocol ProcessCommandExecuting: Sendable {
    func execute(executablePath: String, arguments: [String]) -> ProcessExecutionResult
}

public struct ProcessCommandExecutor: ProcessCommandExecuting {
    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 8) {
        self.timeout = timeout
    }

    public func execute(executablePath: String, arguments: [String]) -> ProcessExecutionResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return ProcessExecutionResult(
                exitCode: 127,
                output: "",
                errorOutput: error.localizedDescription
            )
        }

        let didExit = waitForExit(process)
        if !didExit {
            process.terminate()
            process.waitUntilExit()
        }

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errorOutput = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard didExit else {
            return ProcessExecutionResult(
                exitCode: 124,
                output: output,
                errorOutput: errorOutput.isEmpty ? "process timed out after \(timeout)s" : errorOutput
            )
        }

        return ProcessExecutionResult(
            exitCode: process.terminationStatus,
            output: output,
            errorOutput: errorOutput
        )
    }

    private func waitForExit(_ process: Process) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        return !process.isRunning
    }
}

public struct ShortcutsCommandLinePreflightResult: Equatable, Sendable {
    public let shortcutName: String
    public let shortcutNames: [String]
    public let listResult: ProcessExecutionResult

    public init(shortcutName: String, shortcutNames: [String], listResult: ProcessExecutionResult) {
        self.shortcutName = shortcutName
        self.shortcutNames = shortcutNames
        self.listResult = listResult
    }

    public var exactMatchExists: Bool {
        shortcutNames.contains(shortcutName)
    }

    public var summary: String {
        guard listResult.didSucceed else {
            return "list failed: \(listResult.summary)"
        }

        let match = exactMatchExists ? "found" : "missing"
        let sample = shortcutNames.prefix(5).joined(separator: ", ")
        let sampleSummary = sample.isEmpty ? "none" : sample
        return "\(match) \"\(shortcutName)\" among \(shortcutNames.count) shortcuts; sample: \(sampleSummary)"
    }
}

public struct ShortcutsCommandLineProbe<Executor: ProcessCommandExecuting>: Sendable {
    private let executor: Executor
    private let executablePath: String

    public init(executor: Executor, executablePath: String = "/usr/bin/shortcuts") {
        self.executor = executor
        self.executablePath = executablePath
    }

    public func listShortcuts() -> ProcessExecutionResult {
        executor.execute(executablePath: executablePath, arguments: ["list"])
    }

    public func preflight(shortcutName: String) -> ShortcutsCommandLinePreflightResult {
        let result = listShortcuts()
        return ShortcutsCommandLinePreflightResult(
            shortcutName: shortcutName,
            shortcutNames: Self.shortcutNames(from: result.output),
            listResult: result
        )
    }

    public func runShortcut(named name: String) -> ProcessExecutionResult {
        executor.execute(executablePath: executablePath, arguments: ["run", name])
    }

    public static func shortcutNames(from output: String) -> [String] {
        output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

public extension ShortcutsCommandLineProbe where Executor == ProcessCommandExecutor {
    init() {
        self.init(executor: ProcessCommandExecutor())
    }
}

public struct ActiveSpaceSwitchObservation: Equatable, Sendable {
    public let command: SwitchCommand
    public let didExecuteCommand: Bool
    public let beforeChangeCount: Int
    public let afterChangeCount: Int

    public init(
        command: SwitchCommand,
        didExecuteCommand: Bool,
        beforeChangeCount: Int,
        afterChangeCount: Int
    ) {
        self.command = command
        self.didExecuteCommand = didExecuteCommand
        self.beforeChangeCount = beforeChangeCount
        self.afterChangeCount = afterChangeCount
    }

    public var observedChangeCount: Int {
        max(0, afterChangeCount - beforeChangeCount)
    }

    public var didObserveSpaceChange: Bool {
        observedChangeCount > 0
    }

    public var summary: String {
        let posted = didExecuteCommand ? "posted" : "blocked"
        let observed = didObserveSpaceChange ? "observed \(observedChangeCount)" : "observed none"
        return "\(command) \(posted), active-space notifications \(beforeChangeCount)->\(afterChangeCount) (\(observed))"
    }
}

public struct HiddenSwitchTimingConfiguration: Equatable, Sendable {
    public let hideSettleDelay: TimeInterval
    public let focusDelay: TimeInterval
    public let switchDelay: TimeInterval
    public let transitionSettleDelay: TimeInterval
    public let restoreDelay: TimeInterval
    public let observerWait: TimeInterval

    public init(
        hideSettleDelay: TimeInterval = 0.02,
        focusDelay: TimeInterval,
        switchDelay: TimeInterval,
        transitionSettleDelay: TimeInterval = 0.10,
        restoreDelay: TimeInterval = 0.04,
        observerWait: TimeInterval
    ) {
        self.hideSettleDelay = hideSettleDelay
        self.focusDelay = focusDelay
        self.switchDelay = switchDelay
        self.transitionSettleDelay = transitionSettleDelay
        self.restoreDelay = restoreDelay
        self.observerWait = observerWait
    }

    public func estimatedExecutorDuration(displayCount: Int) -> TimeInterval {
        let targetCount = max(0, displayCount)
        return hideSettleDelay +
            Double(max(0, targetCount - 1)) * focusDelay +
            Double(targetCount) * switchDelay +
            transitionSettleDelay +
            restoreDelay
    }

    public static let optimizedCandidate = HiddenSwitchTimingConfiguration(
        focusDelay: 0.01,
        switchDelay: 0.20,
        observerWait: 0.85
    )

    public static let conservativeCandidate = HiddenSwitchTimingConfiguration(
        hideSettleDelay: 0.02,
        focusDelay: 0.01,
        switchDelay: 0.21,
        transitionSettleDelay: 0.14,
        restoreDelay: 0.04,
        observerWait: 0.85
    )

    public var summary: String {
        "hide=\(Self.format(hideSettleDelay)) focus=\(Self.format(focusDelay)) switch=\(Self.format(switchDelay)) transition=\(Self.format(transitionSettleDelay)) restore=\(Self.format(restoreDelay)) wait=\(Self.format(observerWait))"
    }

    private static func format(_ value: TimeInterval) -> String {
        String(format: "%.2f", value)
    }
}

public struct SpikeActiveSpaceObservedRun: Equatable, Sendable {
    public let didPost: Bool
    public let beforeChangeCount: Int
    public let afterChangeCount: Int

    public init(didPost: Bool, beforeChangeCount: Int, afterChangeCount: Int) {
        self.didPost = didPost
        self.beforeChangeCount = beforeChangeCount
        self.afterChangeCount = afterChangeCount
    }
}

public protocol SpikeActiveSpaceChangeObserving: Sendable {
    func runObservingChanges(wait: TimeInterval, action: () -> Bool) -> SpikeActiveSpaceObservedRun
}

public struct SpikeNSWorkspaceActiveSpaceChangeObserver: SpikeActiveSpaceChangeObserving {
    public init() {}

    public func runObservingChanges(wait: TimeInterval, action: () -> Bool) -> SpikeActiveSpaceObservedRun {
        let counter = SpikeNSWorkspaceActiveSpaceChangeCounter()
        let before = counter.changeCount
        let didPost = action()
        RunLoop.current.run(until: Date().addingTimeInterval(wait))
        return SpikeActiveSpaceObservedRun(
            didPost: didPost,
            beforeChangeCount: before,
            afterChangeCount: counter.changeCount
        )
    }
}

private final class SpikeNSWorkspaceActiveSpaceChangeCounter: @unchecked Sendable {
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

public struct AckingHiddenSpaceCommandRunner: Sendable {
    private let executor: any SpaceCommandExecuting
    private let targetProvider: any DisplaySwitchTargetProviding
    private let activeSpaceObserver: any ActiveSpaceChangeObserving
    private let windowSnapshotProvider: any WindowListSnapshotProviding
    private let timing: HiddenSwitchTimingConfiguration

    public init(
        timing: HiddenSwitchTimingConfiguration = .optimizedCandidate,
        targetProvider: any DisplaySwitchTargetProviding = CGDisplaySwitchTargetProvider(),
        activeSpaceObserver: any ActiveSpaceChangeObserving = NSWorkspaceActiveSpaceChangeObserver(),
        windowSnapshotProvider: any WindowListSnapshotProviding = CGWindowListSnapshotProvider()
    ) {
        self.timing = timing
        self.targetProvider = targetProvider
        self.activeSpaceObserver = activeSpaceObserver
        self.windowSnapshotProvider = windowSnapshotProvider
        self.executor = HiddenCursorDisplaySpaceCommandExecutor(
            targetProvider: targetProvider,
            hideSettleDelay: timing.hideSettleDelay,
            focusDelay: timing.focusDelay,
            switchDelay: timing.switchDelay,
            transitionSettleDelay: timing.transitionSettleDelay,
            restoreDelay: timing.restoreDelay
        )
    }

    public init(
        executor: any SpaceCommandExecuting,
        targetProvider: any DisplaySwitchTargetProviding,
        activeSpaceObserver: any ActiveSpaceChangeObserving,
        windowSnapshotProvider: any WindowListSnapshotProviding,
        timing: HiddenSwitchTimingConfiguration
    ) {
        self.executor = executor
        self.targetProvider = targetProvider
        self.activeSpaceObserver = activeSpaceObserver
        self.windowSnapshotProvider = windowSnapshotProvider
        self.timing = timing
    }

    public func executeWithDiagnostics(_ command: SwitchCommand) -> AckingHiddenSwitchProbeResult {
        let beforeWindowSnapshot = windowSnapshotProvider.snapshot()
        let displayTargetCount = targetProvider.targetPoints().count
        let startedAt = Date()
        let observedRun = activeSpaceObserver.runObservingChanges(wait: timing.observerWait) {
            executor.execute(command)
        }
        let afterWindowSnapshot = windowSnapshotProvider.snapshot()
        let observation = ActiveSpaceSwitchObservation(
            command: command,
            didExecuteCommand: observedRun.didPost,
            beforeChangeCount: observedRun.beforeChangeCount,
            afterChangeCount: observedRun.afterChangeCount
        )

        return AckingHiddenSwitchProbeResult(
            command: command,
            timing: timing,
            displayTargetCount: displayTargetCount,
            didPost: observedRun.didPost,
            activeSpaceObservation: observation,
            windowDiff: WindowListDiffResult(before: beforeWindowSnapshot, after: afterWindowSnapshot),
            elapsedSeconds: Date().timeIntervalSince(startedAt)
        )
    }
}

extension AckingHiddenSpaceCommandRunner: SpaceCommandExecuting {
    public func execute(_ command: SwitchCommand) -> Bool {
        executeWithDiagnostics(command).isAckConfirmedSuccess
    }
}

public struct AckingHiddenSwitchProbeResult: Equatable, Sendable {
    public let command: SwitchCommand
    public let timing: HiddenSwitchTimingConfiguration
    public let displayTargetCount: Int
    public let didPost: Bool
    public let activeSpaceObservation: ActiveSpaceSwitchObservation
    public let windowDiff: WindowListDiffResult
    public let elapsedSeconds: TimeInterval

    public init(
        command: SwitchCommand,
        timing: HiddenSwitchTimingConfiguration,
        displayTargetCount: Int,
        didPost: Bool,
        activeSpaceObservation: ActiveSpaceSwitchObservation,
        windowDiff: WindowListDiffResult,
        elapsedSeconds: TimeInterval
    ) {
        self.command = command
        self.timing = timing
        self.displayTargetCount = displayTargetCount
        self.didPost = didPost
        self.activeSpaceObservation = activeSpaceObservation
        self.windowDiff = windowDiff
        self.elapsedSeconds = elapsedSeconds
    }

    public var expectedNotificationCount: Int {
        max(1, displayTargetCount)
    }

    public var didAcknowledgeAllTargets: Bool {
        activeSpaceObservation.observedChangeCount >= expectedNotificationCount
    }

    public var isAckConfirmedSuccess: Bool {
        didPost && didAcknowledgeAllTargets && windowDiff.didChangeVisibleWindows
    }

    public var summary: String {
        let ack = "\(activeSpaceObservation.observedChangeCount)/\(expectedNotificationCount)"
        let fingerprint = windowDiff.didChangeVisibleWindows ? "changed" : "unchanged"
        let posted = didPost ? "posted" : "failed"
        let confirmation = isAckConfirmedSuccess ? "ack confirmed" : "ack unconfirmed"
        return "\(command) \(posted), \(confirmation), ack \(ack), fingerprint \(fingerprint), elapsed \(String(format: "%.2f", elapsedSeconds))s, \(timing.summary)"
    }
}

public struct WindowListSnapshot: Equatable, Sendable {
    public let onScreenCount: Int
    public let allCount: Int
    public let onScreenOwners: [String]
    public let onScreenWindowSignatures: [String]

    public init(
        onScreenCount: Int,
        allCount: Int,
        onScreenOwners: [String],
        onScreenWindowSignatures: [String] = []
    ) {
        self.onScreenCount = onScreenCount
        self.allCount = allCount
        self.onScreenOwners = onScreenOwners
        self.onScreenWindowSignatures = onScreenWindowSignatures
    }
}

public struct WindowListDiffResult: Equatable, Sendable {
    public let before: WindowListSnapshot
    public let after: WindowListSnapshot
    public let appearedOwners: [String]
    public let disappearedOwners: [String]
    public let appearedWindows: [String]
    public let disappearedWindows: [String]

    public init(before: WindowListSnapshot, after: WindowListSnapshot) {
        self.before = before
        self.after = after
        let beforeOwners = Set(before.onScreenOwners)
        let afterOwners = Set(after.onScreenOwners)
        let beforeWindows = Set(before.onScreenWindowSignatures)
        let afterWindows = Set(after.onScreenWindowSignatures)
        appearedOwners = Array(afterOwners.subtracting(beforeOwners)).sorted()
        disappearedOwners = Array(beforeOwners.subtracting(afterOwners)).sorted()
        appearedWindows = Array(afterWindows.subtracting(beforeWindows)).sorted()
        disappearedWindows = Array(beforeWindows.subtracting(afterWindows)).sorted()
    }

    public var didChangeVisibleWindows: Bool {
        before.onScreenCount != after.onScreenCount ||
            !appearedOwners.isEmpty ||
            !disappearedOwners.isEmpty ||
            !appearedWindows.isEmpty ||
            !disappearedWindows.isEmpty
    }

    public var summary: String {
        let appearedWindowSample = appearedWindows.prefix(3).joined(separator: ", ")
        let disappearedWindowSample = disappearedWindows.prefix(3).joined(separator: ", ")
        let windowSummary = appearedWindows.isEmpty && disappearedWindows.isEmpty
            ? "windows unchanged"
            : "windows +[\(appearedWindowSample)] -[\(disappearedWindowSample)]"
        return "onScreen \(before.onScreenCount)->\(after.onScreenCount), all \(before.allCount)->\(after.allCount), owners +\(appearedOwners) -\(disappearedOwners), \(windowSummary)"
    }
}

public protocol WindowListSnapshotProviding: Sendable {
    func snapshot() -> WindowListSnapshot
}

public struct CGWindowListSnapshotProvider: WindowListSnapshotProviding {
    public init() {}

    public func snapshot() -> WindowListSnapshot {
        let onScreenWindows = windows(options: [.optionOnScreenOnly, .excludeDesktopElements])
        let allWindows = windows(options: .optionAll)
        let owners = onScreenWindows
            .compactMap { $0[kCGWindowOwnerName as String] as? String }
            .filter { !$0.isEmpty }
            .sorted()
        let signatures = onScreenWindows
            .compactMap(Self.windowSignature)
            .sorted()

        return WindowListSnapshot(
            onScreenCount: onScreenWindows.count,
            allCount: allWindows.count,
            onScreenOwners: owners,
            onScreenWindowSignatures: signatures
        )
    }

    private func windows(options: CGWindowListOption) -> [[String: Any]] {
        CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
    }

    private static func windowSignature(from dictionary: [String: Any]) -> String? {
        guard let windowNumber = dictionary[kCGWindowNumber as String] as? Int else {
            return nil
        }

        let owner = dictionary[kCGWindowOwnerName as String] as? String ?? "unknown"
        let layer = dictionary[kCGWindowLayer as String] as? Int ?? 0
        let bounds = dictionary[kCGWindowBounds as String] as? [String: CGFloat]
        let x = bounds?["X"].map { Int($0.rounded()) } ?? 0
        let y = bounds?["Y"].map { Int($0.rounded()) } ?? 0
        let width = bounds?["Width"].map { Int($0.rounded()) } ?? 0
        let height = bounds?["Height"].map { Int($0.rounded()) } ?? 0
        return "\(owner)#\(windowNumber)@L\(layer)[\(x),\(y),\(width),\(height)]"
    }
}
