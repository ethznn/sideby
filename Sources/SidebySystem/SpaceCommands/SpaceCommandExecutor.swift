import AppKit
import CoreGraphics
import CoreServices
import Foundation
import SidebyCore

public protocol KeyEventPosting: Sendable {
    @discardableResult
    func postKey(virtualKey: CGKeyCode, flags: CGEventFlags) -> Bool
}

public struct CGEventKeyEventPoster: KeyEventPosting {
    private let tap: CGEventTapLocation
    private let sourceStateID: CGEventSourceStateID?
    private let sendsModifierFlagEvents: Bool

    public init(
        tap: CGEventTapLocation = .cghidEventTap,
        sourceStateID: CGEventSourceStateID? = .hidSystemState,
        sendsModifierFlagEvents: Bool = true
    ) {
        self.tap = tap
        self.sourceStateID = sourceStateID
        self.sendsModifierFlagEvents = sendsModifierFlagEvents
    }

    public func postKey(virtualKey: CGKeyCode, flags: CGEventFlags) -> Bool {
        guard CGPreflightPostEventAccess() || CGRequestPostEventAccess() else {
            return false
        }

        let source: CGEventSource? = sourceStateID.flatMap { CGEventSource(stateID: $0) }
        let controlKeyCode: CGKeyCode = 59

        if sendsModifierFlagEvents, flags.contains(.maskControl) {
            guard
                let controlDown = CGEvent(keyboardEventSource: source, virtualKey: controlKeyCode, keyDown: true)
            else {
                return false
            }

            controlDown.type = .flagsChanged
            controlDown.flags = .maskControl
            controlDown.post(tap: tap)
            Thread.sleep(forTimeInterval: 0.03)
        }

        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false)
        else {
            return false
        }

        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: tap)
        Thread.sleep(forTimeInterval: 0.03)
        keyUp.post(tap: tap)
        Thread.sleep(forTimeInterval: 0.03)

        if sendsModifierFlagEvents,
           flags.contains(.maskControl),
           let controlUp = CGEvent(keyboardEventSource: source, virtualKey: controlKeyCode, keyDown: false) {
            controlUp.type = .flagsChanged
            controlUp.flags = []
            controlUp.post(tap: tap)
        }

        return true
    }
}

public protocol AppleScriptRunning: Sendable {
    @discardableResult
    func run(source: String) -> Bool
}

public struct NSAppleScriptRunner: AppleScriptRunning {
    public init() {}

    public func run(source: String) -> Bool {
        guard let script = NSAppleScript(source: source) else {
            return false
        }

        var error: NSDictionary?
        _ = script.executeAndReturnError(&error)
        return error == nil
    }
}

public struct AppleScriptKeyEventPoster<Runner: AppleScriptRunning>: KeyEventPosting {
    private let runner: Runner

    public init(runner: Runner) {
        self.runner = runner
    }

    public func postKey(virtualKey: CGKeyCode, flags: CGEventFlags) -> Bool {
        runner.run(source: Self.script(virtualKey: virtualKey, flags: flags))
    }

    static func script(virtualKey: CGKeyCode, flags: CGEventFlags) -> String {
        let modifierClause = flags.contains(.maskControl) ? " using {control down}" : ""
        return """
        tell application "System Events"
            key code \(virtualKey)\(modifierClause)
        end tell
        """
    }
}

public extension AppleScriptKeyEventPoster where Runner == NSAppleScriptRunner {
    init() {
        self.init(runner: NSAppleScriptRunner())
    }
}

public struct AppleScriptModifierNeutralizingSpaceCommandExecutor<Runner: AppleScriptRunning>: SpaceCommandExecuting {
    private let modifiers: ModifierFlags
    private let runner: Runner

    public init(
        modifiers: ModifierFlags,
        runner: Runner
    ) {
        self.modifiers = modifiers
        self.runner = runner
    }

    public func execute(_ command: SwitchCommand) -> Bool {
        runner.run(source: Self.script(command: command, modifiers: modifiers))
    }

    static func script(command: SwitchCommand, modifiers: ModifierFlags) -> String {
        let releaseLines = Self.releaseLines(for: modifiers)
        let commandLines = releaseLines.isEmpty
            ? [Self.keyCodeLine(for: command)]
            : releaseLines + ["delay 0.02", Self.keyCodeLine(for: command)]
        let indentedLines = commandLines
            .map { "    \($0)" }
            .joined(separator: "\n")

        return """
        tell application "System Events"
        \(indentedLines)
        end tell
        """
    }

    private static func releaseLines(for modifiers: ModifierFlags) -> [String] {
        var lines: [String] = []
        if modifiers.contains(.shift) {
            lines.append("key up shift")
        }
        if modifiers.contains(.control) {
            lines.append("key up control")
        }
        if modifiers.contains(.option) {
            lines.append("key up option")
        }
        if modifiers.contains(.command) {
            lines.append("key up command")
        }
        return lines
    }

    private static func keyCodeLine(for command: SwitchCommand) -> String {
        "key code \(keyCode(for: command)) using {control down}"
    }

    private static func keyCode(for command: SwitchCommand) -> CGKeyCode {
        switch command {
        case .previous:
            123
        case .next:
            124
        }
    }
}

public extension AppleScriptModifierNeutralizingSpaceCommandExecutor where Runner == NSAppleScriptRunner {
    init(modifiers: ModifierFlags) {
        self.init(modifiers: modifiers, runner: NSAppleScriptRunner())
    }
}

public struct PrivateCGEventSpaceCommandExecutor<Poster: KeyEventPosting>: SpaceCommandExecuting {
    private let poster: Poster

    public init(poster: Poster) {
        self.poster = poster
    }

    public func execute(_ command: SwitchCommand) -> Bool {
        poster.postKey(virtualKey: keyCode(for: command), flags: .maskControl)
    }

    private func keyCode(for command: SwitchCommand) -> CGKeyCode {
        switch command {
        case .previous:
            123
        case .next:
            124
        }
    }
}

public extension PrivateCGEventSpaceCommandExecutor where Poster == CGEventKeyEventPoster {
    init() {
        self.init(
            poster: CGEventKeyEventPoster(
                tap: .cghidEventTap,
                sourceStateID: .privateState,
                sendsModifierFlagEvents: false
            )
        )
    }
}

public final class EventTapModifierRewritingSpaceCommandExecutor<Base: SpaceCommandExecuting>: SpaceCommandExecuting, @unchecked Sendable {
    private let baseExecutor: Base
    private let tapLocation: CGEventTapLocation

    public init(
        baseExecutor: Base,
        tapLocation: CGEventTapLocation = .cgSessionEventTap
    ) {
        self.baseExecutor = baseExecutor
        self.tapLocation = tapLocation
    }

    public func execute(_ command: SwitchCommand) -> Bool {
        let session = TemporaryModifierRewriteEventTap(tapLocation: tapLocation)
        guard session.start() else {
            return false
        }
        defer { session.stop() }
        return baseExecutor.execute(command)
    }
}

enum EventTapModifierRewriter {
    static func rewrittenFlags(
        type: CGEventType,
        keyCode: CGKeyCode,
        originalFlags _: CGEventFlags
    ) -> CGEventFlags? {
        guard type == .keyDown || type == .keyUp else {
            return nil
        }
        guard keyCode == 123 || keyCode == 124 else {
            return nil
        }
        return .maskControl
    }
}

private final class TemporaryModifierRewriteEventTap: @unchecked Sendable {
    private let tapLocation: CGEventTapLocation
    private let ready = DispatchSemaphore(value: 0)
    private let stopped = DispatchSemaphore(value: 0)
    private var runLoop: CFRunLoop?
    private var eventTap: CFMachPort?
    private var thread: Thread?
    private let lock = NSLock()
    private var shouldStop = false
    private var didStart = false

    init(tapLocation: CGEventTapLocation) {
        self.tapLocation = tapLocation
    }

    func start() -> Bool {
        let thread = Thread { [weak self] in
            self?.run()
        }
        thread.name = "SidebyModifierRewriteEventTap"
        self.thread = thread
        thread.start()

        guard ready.wait(timeout: .now() + 0.4) == .success else {
            stop()
            return false
        }

        lock.lock()
        let started = didStart
        lock.unlock()
        return started
    }

    func stop() {
        lock.lock()
        shouldStop = true
        let runLoop = runLoop
        lock.unlock()

        if let runLoop {
            CFRunLoopWakeUp(runLoop)
        }

        _ = stopped.wait(timeout: .now() + 0.4)
    }

    private func run() {
        lock.lock()
        runLoop = CFRunLoopGetCurrent()
        lock.unlock()

        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
        let tap = CGEvent.tapCreate(
            tap: tapLocation,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: Self.callback,
            userInfo: nil
        )

        guard let tap,
              let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        else {
            ready.signal()
            stopped.signal()
            return
        }

        eventTap = tap
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        lock.lock()
        didStart = true
        lock.unlock()
        ready.signal()

        while true {
            lock.lock()
            let shouldStop = shouldStop
            lock.unlock()
            if shouldStop {
                break
            }
            CFRunLoopRunInMode(.defaultMode, 0.05, true)
        }

        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        stopped.signal()
    }

    private static let callback: CGEventTapCallBack = { _, type, event, _ in
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        if let rewrittenFlags = EventTapModifierRewriter.rewrittenFlags(
            type: type,
            keyCode: keyCode,
            originalFlags: event.flags
        ) {
            event.flags = rewrittenFlags
        }

        return Unmanaged.passUnretained(event)
    }
}

public struct SystemEventsAutomationProbe<Runner: AppleScriptRunning>: Sendable {
    private let runner: Runner

    public init(runner: Runner) {
        self.runner = runner
    }

    public func requestAccess() -> Bool {
        runner.run(source: Self.script)
    }

    public static var script: String {
        """
        tell application "System Events"
            count processes
        end tell
        """
    }
}

public extension SystemEventsAutomationProbe where Runner == NSAppleScriptRunner {
    init() {
        self.init(runner: NSAppleScriptRunner())
    }
}

public struct AutomationPermissionResult: Equatable, Sendable {
    public let statusCode: Int32

    public init(statusCode: Int32) {
        self.statusCode = statusCode
    }

    public var isGranted: Bool {
        statusCode == Int32(noErr)
    }

    public var statusText: String {
        if statusCode == Int32(noErr) {
            return "granted"
        }
        if statusCode == Int32(errAEEventNotPermitted) {
            return "blocked (-1743)"
        }
        if statusCode == Int32(errAEEventWouldRequireUserConsent) {
            return "needs consent (-1744)"
        }
        if statusCode == Int32(procNotFound) {
            return "System Events not running (-600)"
        }
        return "failed (\(statusCode))"
    }
}

public struct SystemEventsAutomationPermissionProbe: Sendable {
    private let targetBundleIdentifier: String
    private let targetProcessIdentifier: pid_t?

    public init(
        targetBundleIdentifier: String = "com.apple.systemevents",
        targetProcessIdentifier: pid_t? = nil
    ) {
        self.targetBundleIdentifier = targetBundleIdentifier
        self.targetProcessIdentifier = targetProcessIdentifier
    }

    public func requestAccess() -> AutomationPermissionResult {
        determinePermission(askUserIfNeeded: true)
    }

    public func checkAccessWithoutPrompt() -> AutomationPermissionResult {
        determinePermission(askUserIfNeeded: false)
    }

    private func determinePermission(askUserIfNeeded: Bool) -> AutomationPermissionResult {
        var target = AEAddressDesc()
        let createStatus = createTargetDescriptor(&target)
        guard createStatus == noErr else {
            return AutomationPermissionResult(statusCode: Int32(createStatus))
        }
        defer {
            AEDisposeDesc(&target)
        }

        let status = AEDeterminePermissionToAutomateTarget(
            &target,
            AEEventClass(typeWildCard),
            AEEventID(typeWildCard),
            askUserIfNeeded
        )
        return AutomationPermissionResult(statusCode: status)
    }

    private func createTargetDescriptor(_ target: inout AEAddressDesc) -> OSStatus {
        if var processID = targetProcessIdentifier {
            return OSStatus(AECreateDesc(
                DescType(typeKernelProcessID),
                &processID,
                MemoryLayout<pid_t>.size,
                &target
            ))
        }

        let status = targetBundleIdentifier.withCString { bundleIDPointer in
            OSStatus(AECreateDesc(
                DescType(typeApplicationBundleID),
                bundleIDPointer,
                targetBundleIdentifier.utf8.count,
                &target
            ))
        }
        return status
    }
}

public protocol DisplaySwitchTargetProviding: Sendable {
    func targetPoints() -> [CGPoint]
}

public struct DisplaySwitchTargetCandidate: Equatable, Sendable {
    public let stableID: String
    public let isMain: Bool
    public let originX: CGFloat
    public let point: CGPoint

    public init(stableID: String, isMain: Bool, originX: CGFloat, point: CGPoint) {
        self.stableID = stableID
        self.isMain = isMain
        self.originX = originX
        self.point = point
    }
}

public enum DisplaySwitchTargetOrdering {
    public static func targetPoints(
        from candidates: [DisplaySwitchTargetCandidate],
        includedStableIDs: Set<String>? = nil
    ) -> [CGPoint] {
        candidates
            .filter { candidate in
                guard let includedStableIDs else {
                    return true
                }
                return includedStableIDs.contains(candidate.stableID)
            }
            .sorted { lhs, rhs in
                if lhs.isMain != rhs.isMain {
                    return lhs.isMain
                }
                return lhs.originX < rhs.originX
            }
            .map(\.point)
    }
}

public struct CGDisplaySwitchTargetProvider: DisplaySwitchTargetProviding {
    private let includedStableIDs: Set<String>?

    public init(includedStableIDs: Set<String>? = nil) {
        self.includedStableIDs = includedStableIDs
    }

    public func targetPoints() -> [CGPoint] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return []
        }

        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displayIDs, &count) == .success else {
            return []
        }

        return DisplaySwitchTargetOrdering.targetPoints(
            from: displayIDs.map(Self.candidate(for:)),
            includedStableIDs: includedStableIDs
        )
    }

    private static func candidate(for id: CGDirectDisplayID) -> DisplaySwitchTargetCandidate {
        let bounds = CGDisplayBounds(id)
        let snapshot = DisplaySnapshot(
            displayID: id,
            name: "Display \(id)",
            isPrimary: CGDisplayIsMain(id) != 0,
            isBuiltin: CGDisplayIsBuiltin(id) != 0,
            vendorNumber: CGDisplayVendorNumber(id),
            modelNumber: CGDisplayModelNumber(id),
            serialNumber: CGDisplaySerialNumber(id)
        )
        return DisplaySwitchTargetCandidate(
            stableID: DisplayLayoutMapper.stableID(for: snapshot),
            isMain: snapshot.isPrimary,
            originX: bounds.origin.x,
            point: focusPoint(in: bounds)
        )
    }

    public static func focusPoint(in bounds: CGRect) -> CGPoint {
        let inset = min(CGFloat(2), max(CGFloat(0), min(bounds.width, bounds.height) / 2))
        return CGPoint(x: bounds.maxX - inset, y: bounds.maxY - inset)
    }
}

public protocol CursorPositioning: Sendable {
    func currentLocation() -> CGPoint?
    func move(to point: CGPoint)
}

public struct CGCursorPositioner: CursorPositioning {
    public init() {}

    public func currentLocation() -> CGPoint? {
        CGEvent(source: nil)?.location
    }

    public func move(to point: CGPoint) {
        guard let displayID = displayID(containing: point) else {
            CGWarpMouseCursorPosition(point)
            return
        }

        let bounds = CGDisplayBounds(displayID)
        let localPoint = CGPoint(
            x: point.x - bounds.origin.x,
            y: point.y - bounds.origin.y
        )
        guard CGDisplayMoveCursorToPoint(displayID, localPoint) == .success else {
            CGWarpMouseCursorPosition(point)
            return
        }
    }

    private func displayID(containing point: CGPoint) -> CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return nil
        }

        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displayIDs, &count) == .success else {
            return nil
        }

        return displayIDs
            .prefix(Int(count))
            .first { CGDisplayBounds($0).contains(point) }
    }
}

public protocol CursorVisibilityControlling: Sendable {
    func hide() -> Bool
    func show() -> Bool
}

public protocol CursorShielding: Sendable {
    func begin() -> Bool
    func end()
}

public struct NoopCursorShield: CursorShielding {
    public init() {}

    public func begin() -> Bool {
        true
    }

    public func end() {}
}

public final class AppKitTransparentCursorShield: CursorShielding, @unchecked Sendable {
    @MainActor private static let transparentCursor = NSCursor(
        image: NSImage(size: NSSize(width: 16, height: 16)),
        hotSpot: .zero
    )

    private var panels: [NSPanel] = []

    public init() {}

    public func begin() -> Bool {
        runOnMain { [self] in
            closePanels()
            NSApp?.activate(ignoringOtherApps: true)
            Self.transparentCursor.set()
            NSCursor.setHiddenUntilMouseMoves(true)

            panels = NSScreen.screens.map { screen in
                let panel = TransparentCursorShieldPanel(
                    contentRect: screen.frame,
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false
                )
                let view = TransparentCursorShieldView(cursor: Self.transparentCursor)
                view.frame = CGRect(origin: .zero, size: screen.frame.size)
                panel.contentView = view
                panel.backgroundColor = .clear
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
                panel.hasShadow = false
                panel.ignoresMouseEvents = false
                panel.isOpaque = false
                panel.isReleasedWhenClosed = false
                panel.level = .screenSaver
                panel.acceptsMouseMovedEvents = true
                panel.orderFrontRegardless()
                panel.makeKeyAndOrderFront(nil)
                panel.invalidateCursorRects(for: view)
                return panel
            }

            Self.transparentCursor.set()
            return !panels.isEmpty
        }
    }

    public func end() {
        runOnMain { [self] in
            closePanels()
            NSCursor.arrow.set()
        }
    }

    @MainActor private func closePanels() {
        panels.forEach { $0.close() }
        panels.removeAll()
    }

    private func runOnMain<T: Sendable>(_ action: @MainActor @escaping () -> T) -> T {
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

@MainActor private final class TransparentCursorShieldPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor private final class TransparentCursorShieldView: NSView {
    private let cursor: NSCursor

    init(cursor: NSCursor) {
        self.cursor = cursor
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: cursor)
    }

    override func cursorUpdate(with event: NSEvent) {
        cursor.set()
    }

    override func mouseMoved(with event: NSEvent) {
        cursor.set()
    }
}

public protocol MouseCursorAssociationControlling: Sendable {
    func disconnect() -> Bool
    func connect() -> Bool
}

public struct CGMouseCursorAssociationController: MouseCursorAssociationControlling {
    public init() {}

    public func disconnect() -> Bool {
        CGAssociateMouseAndMouseCursorPosition(0) == .success
    }

    public func connect() -> Bool {
        CGAssociateMouseAndMouseCursorPosition(1) == .success
    }
}

public protocol CursorVisibilityDisplayProviding: Sendable {
    func displayIDs() -> [CGDirectDisplayID]
}

public struct CGActiveDisplayIDProvider: CursorVisibilityDisplayProviding {
    public init() {}

    public func displayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return []
        }

        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displayIDs, &count) == .success else {
            return []
        }

        return Array(displayIDs.prefix(Int(count)))
    }
}

public protocol CursorVisibilityApplying: Sendable {
    func hide(displayID: CGDirectDisplayID) -> Bool
    func show(displayID: CGDirectDisplayID) -> Bool
}

public struct CGCursorVisibilityApplier: CursorVisibilityApplying {
    public init() {}

    public func hide(displayID: CGDirectDisplayID) -> Bool {
        CGDisplayHideCursor(displayID) == .success
    }

    public func show(displayID: CGDirectDisplayID) -> Bool {
        CGDisplayShowCursor(displayID) == .success
    }
}

public struct CGCursorVisibilityController: CursorVisibilityControlling {
    private let displayProvider: any CursorVisibilityDisplayProviding
    private let applier: any CursorVisibilityApplying
    @MainActor private static let transparentCursor = NSCursor(
        image: NSImage(size: NSSize(width: 16, height: 16)),
        hotSpot: .zero
    )

    public init(
        displayProvider: any CursorVisibilityDisplayProviding = CGActiveDisplayIDProvider(),
        applier: any CursorVisibilityApplying = CGCursorVisibilityApplier()
    ) {
        self.displayProvider = displayProvider
        self.applier = applier
    }

    public func hide() -> Bool {
        applyAppKitCursorOperation {
            NSApp?.activate(ignoringOtherApps: true)
            Self.transparentCursor.set()
            NSCursor.setHiddenUntilMouseMoves(true)
            NSCursor.hide()
        }
        return applyToTargetDisplays { displayID in
            applier.hide(displayID: displayID)
        }
    }

    public func show() -> Bool {
        applyAppKitCursorOperation {
            NSCursor.unhide()
            NSCursor.setHiddenUntilMouseMoves(false)
            NSCursor.arrow.set()
        }
        return applyToTargetDisplays { displayID in
            applier.show(displayID: displayID)
        }
    }

    private func applyToTargetDisplays(_ operation: (CGDirectDisplayID) -> Bool) -> Bool {
        let displayIDs = targetDisplayIDs()
        return displayIDs.reduce(true) { didSucceed, displayID in
            operation(displayID) && didSucceed
        }
    }

    private func targetDisplayIDs() -> [CGDirectDisplayID] {
        let displayIDs = displayProvider.displayIDs()
        if displayIDs.isEmpty {
            return [CGMainDisplayID()]
        }

        return displayIDs
    }

    private func applyAppKitCursorOperation(_ operation: @MainActor @escaping () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                operation()
            }
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    operation()
                }
            }
        }
    }
}

public protocol PostEventAccessChecking: Sendable {
    func hasOrRequestAccess() -> Bool
}

public struct CGPostEventAccessChecker: PostEventAccessChecking {
    public init() {}

    public func hasOrRequestAccess() -> Bool {
        CGPreflightPostEventAccess() || CGRequestPostEventAccess()
    }
}

public struct CoordinatedDisplaySpaceCommandExecutor: SpaceCommandExecuting {
    private let baseExecutor: any SpaceCommandExecuting
    private let targetProvider: any DisplaySwitchTargetProviding
    private let cursor: any CursorPositioning
    private let postEventAccessChecker: any PostEventAccessChecking
    private let focusDelay: TimeInterval
    private let switchDelay: TimeInterval

    public init(
        baseExecutor: any SpaceCommandExecuting = MacSpaceCommandExecutor(poster: AppleScriptKeyEventPoster()),
        targetProvider: any DisplaySwitchTargetProviding = CGDisplaySwitchTargetProvider(),
        cursor: any CursorPositioning = CGCursorPositioner(),
        postEventAccessChecker: any PostEventAccessChecking = CGPostEventAccessChecker(),
        focusDelay: TimeInterval = 0.08,
        switchDelay: TimeInterval = 0.55
    ) {
        self.baseExecutor = baseExecutor
        self.targetProvider = targetProvider
        self.cursor = cursor
        self.postEventAccessChecker = postEventAccessChecker
        self.focusDelay = focusDelay
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

        let originalLocation = cursor.currentLocation()
        var didExecuteAll = true

        for point in points {
            cursor.move(to: point)
            Thread.sleep(forTimeInterval: focusDelay)
            didExecuteAll = baseExecutor.execute(command) && didExecuteAll
            Thread.sleep(forTimeInterval: switchDelay)
        }

        if let originalLocation {
            cursor.move(to: originalLocation)
        }

        return didExecuteAll
    }
}

public struct HiddenCursorDisplaySpaceCommandExecutor: SpaceCommandExecuting {
    public static let defaultHideSettleDelay: TimeInterval = 0.02
    public static let defaultFocusDelay: TimeInterval = 0.01
    public static let defaultSwitchDelay: TimeInterval = 0.20
    public static let defaultTransitionSettleDelay: TimeInterval = 0.10
    public static let defaultRestoreDelay: TimeInterval = 0.04

    private let baseExecutor: any SpaceCommandExecuting
    private let targetProvider: any DisplaySwitchTargetProviding
    private let cursor: any CursorPositioning
    private let visibilityController: any CursorVisibilityControlling
    private let cursorShield: any CursorShielding
    private let cursorAssociationController: any MouseCursorAssociationControlling
    private let postEventAccessChecker: any PostEventAccessChecking
    private let hideSettleDelay: TimeInterval
    private let focusDelay: TimeInterval
    private let switchDelay: TimeInterval
    private let transitionSettleDelay: TimeInterval
    private let restoreDelay: TimeInterval

    public init(
        baseExecutor: any SpaceCommandExecuting = MacSpaceCommandExecutor(poster: AppleScriptKeyEventPoster()),
        targetProvider: any DisplaySwitchTargetProviding = CGDisplaySwitchTargetProvider(),
        cursor: any CursorPositioning = CGCursorPositioner(),
        visibilityController: any CursorVisibilityControlling = CGCursorVisibilityController(),
        cursorShield: any CursorShielding = AppKitTransparentCursorShield(),
        cursorAssociationController: any MouseCursorAssociationControlling = CGMouseCursorAssociationController(),
        postEventAccessChecker: any PostEventAccessChecking = CGPostEventAccessChecker(),
        hideSettleDelay: TimeInterval = Self.defaultHideSettleDelay,
        focusDelay: TimeInterval = Self.defaultFocusDelay,
        switchDelay: TimeInterval = Self.defaultSwitchDelay,
        transitionSettleDelay: TimeInterval = Self.defaultTransitionSettleDelay,
        restoreDelay: TimeInterval = Self.defaultRestoreDelay
    ) {
        self.baseExecutor = baseExecutor
        self.targetProvider = targetProvider
        self.cursor = cursor
        self.visibilityController = visibilityController
        self.cursorShield = cursorShield
        self.cursorAssociationController = cursorAssociationController
        self.postEventAccessChecker = postEventAccessChecker
        self.hideSettleDelay = hideSettleDelay
        self.focusDelay = focusDelay
        self.switchDelay = switchDelay
        self.transitionSettleDelay = transitionSettleDelay
        self.restoreDelay = restoreDelay
    }

    public func execute(_ command: SwitchCommand) -> Bool {
        guard postEventAccessChecker.hasOrRequestAccess() else {
            return false
        }

        let points = targetProvider.targetPoints()
        guard !points.isEmpty else {
            return false
        }

        let originalLocation = cursor.currentLocation()
        var hiddenCursorRequestCount = 0
        func hideCursor() {
            _ = visibilityController.hide()
            hiddenCursorRequestCount += 1
        }
        func showCursor() {
            while hiddenCursorRequestCount > 0 {
                _ = visibilityController.show()
                hiddenCursorRequestCount -= 1
            }
        }

        _ = cursorShield.begin()
        hideCursor()
        Thread.sleep(forTimeInterval: hideSettleDelay)
        _ = cursorAssociationController.disconnect()
        hideCursor()
        defer {
            restoreCursor(to: originalLocation, hideCursor: hideCursor)
            hideCursor()
            _ = cursorAssociationController.connect()
            hideCursor()
            cursorShield.end()
            showCursor()
        }

        let orderedPoints = targetPointsForCurrentCursorFirst(points, originalLocation: originalLocation)
        var didExecuteAll = true
        for (index, point) in orderedPoints.enumerated() {
            if index > 0 || originalLocation == nil {
                moveCursorWhileHidden(to: point, hideCursor: hideCursor)
                Thread.sleep(forTimeInterval: focusDelay)
            }
            hideCursor()
            didExecuteAll = baseExecutor.execute(command) && didExecuteAll
            hideCursor()
            Thread.sleep(forTimeInterval: switchDelay)
        }

        Thread.sleep(forTimeInterval: transitionSettleDelay)
        return didExecuteAll
    }

    private func restoreCursor(to originalLocation: CGPoint?, hideCursor: () -> Void) {
        guard let originalLocation else {
            return
        }

        moveCursorWhileHidden(to: originalLocation, hideCursor: hideCursor)
        Thread.sleep(forTimeInterval: restoreDelay)
    }

    private func moveCursorWhileHidden(to point: CGPoint, hideCursor: () -> Void) {
        hideCursor()
        cursor.move(to: point)
        hideCursor()
    }

    private func targetPointsForCurrentCursorFirst(
        _ points: [CGPoint],
        originalLocation: CGPoint?
    ) -> [CGPoint] {
        guard let originalLocation,
              let firstTargetIndex = currentDisplayTargetIndex(
                  in: points,
                  originalLocation: originalLocation
              ) ?? nearestTargetIndex(in: points, originalLocation: originalLocation)
        else {
            return points
        }

        var orderedPoints = points
        let currentPoint = orderedPoints.remove(at: firstTargetIndex)
        orderedPoints.insert(currentPoint, at: 0)
        return orderedPoints
    }

    private func currentDisplayTargetIndex(
        in points: [CGPoint],
        originalLocation: CGPoint
    ) -> Int? {
        let matchingIndices = points.indices.filter { index in
            guard let displayID = displayID(containing: points[index]) else {
                return false
            }

            return CGDisplayBounds(displayID).contains(originalLocation)
        }
        guard matchingIndices.count == 1 else {
            return nil
        }

        return matchingIndices[0]
    }

    private func nearestTargetIndex(
        in points: [CGPoint],
        originalLocation: CGPoint
    ) -> Int? {
        points.indices.min { lhs, rhs in
            distanceSquared(from: originalLocation, to: points[lhs]) <
                distanceSquared(from: originalLocation, to: points[rhs])
        }
    }

    private func displayID(containing point: CGPoint) -> CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return nil
        }

        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displayIDs, &count) == .success else {
            return nil
        }

        return displayIDs
            .prefix(Int(count))
            .first { CGDisplayBounds($0).contains(point) }
    }

    private func distanceSquared(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return dx * dx + dy * dy
    }
}

public struct MacSpaceCommandExecutor<Poster: KeyEventPosting>: SpaceCommandExecuting {
    private let poster: Poster

    public init(poster: Poster = CGEventKeyEventPoster()) {
        self.poster = poster
    }

    public func execute(_ command: SwitchCommand) -> Bool {
        poster.postKey(virtualKey: keyCode(for: command), flags: .maskControl)
    }

    private func keyCode(for command: SwitchCommand) -> CGKeyCode {
        switch command {
        case .previous:
            123
        case .next:
            124
        }
    }
}
