import SidebyCore
import SidebySystem
import SidebyUI
import AppKit
import CoreGraphics
import Darwin
import Foundation
import SwiftUI

@main
struct SidebyDevApp: App {
    @StateObject private var model = DevAppModel()

    init() {
        if DevCommandLineRunner.runIfRequested() {
            Thread.sleep(forTimeInterval: 0.5)
            exit(0)
        }
    }

    var body: some Scene {
        WindowGroup("Sideby Dev", id: "dev-main") {
            DevAppView(model: model)
                .frame(minWidth: 720, minHeight: 560)
                .background(DevWindowBehaviorInstaller())
        }

        MenuBarExtra {
            DevMenuBarControlView(model: model)
        } label: {
            Label("SBS Dev", systemImage: "hammer")
        }
        .menuBarExtraStyle(.window)
    }
}

private struct DevMenuBarControlView: View {
    @ObservedObject var model: DevAppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @State private var menuWindow: NSWindow?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "hammer")
                    .foregroundStyle(.orange)
                Text("SBS Dev")
                    .font(.headline.weight(.semibold))
                Spacer()
                Text("Diagnostics")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color(nsColor: .systemOrange).opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                DevMenuStatusRow(label: "Displays", value: "\(model.displayLayout.displayCount)")
                DevMenuStatusRow(label: "Targets", value: model.selectedDisplaySummary)
                DevMenuStatusRow(label: "Access", value: String(describing: model.permissionState))
                DevMenuStatusRow(label: "Keys", value: model.keyboardCommandSummary)
                DevMenuStatusRow(label: "Last", value: model.lastSwitchResult)
            }

            Divider()

            HStack(spacing: 8) {
                Button("<- Previous") {
                    queueSwitch(.previous)
                }
                Button("Next ->") {
                    queueSwitch(.next)
                }
            }

            Button(model.isSwipeInputListening ? "Stop Listening" : "Start Listening") {
                model.toggleSwipeInputListener()
            }

            Divider()

            HStack(spacing: 8) {
                Button("Open Dev Window") {
                    openWindow(id: "dev-main")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
                Button("Refresh") {
                    model.refresh()
                }
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding()
        .frame(width: 340, alignment: .leading)
        .background {
            DevMenuWindowReader { window in
                menuWindow = window
            }
        }
        .onAppear {
            model.refresh()
        }
    }

    private func queueSwitch(_ command: SwitchCommand) {
        let sourceScreen = menuWindow?.screen
        if model.switchContextWithHiddenCursor(command, preferredFloatingScreen: sourceScreen) {
            closeMenuBarWindow()
        }
    }

    private func closeMenuBarWindow() {
        let window = menuWindow ?? NSApplication.shared.keyWindow
        dismiss()
        window?.orderOut(nil)
        DevMenuBarWindowCloser.closeTransientMenuWindows()
    }
}

private struct DevMenuWindowReader: NSViewRepresentable {
    let onWindowChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            onWindowChange(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            onWindowChange(nsView.window)
        }
    }
}

@MainActor
private enum DevMenuBarWindowCloser {
    static let mainWindowIdentifier = NSUserInterfaceItemIdentifier("sideby-dev-main-window")
    static let floatingPanelIdentifier = NSUserInterfaceItemIdentifier("sideby-dev-floating-panel")

    static func closeTransientMenuWindows() {
        for window in NSApplication.shared.windows {
            guard window.identifier != mainWindowIdentifier,
                  window.identifier != floatingPanelIdentifier else {
                continue
            }

            window.orderOut(nil)
        }
    }
}

private struct DevMenuStatusRow: View {
    let label: String
    let value: String

    var body: some View {
        GridRow {
            Text(label)
                .font(.caption)
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}

@MainActor
private final class DevFloatingMenuPanelController {
    static let shared = DevFloatingMenuPanelController()

    private var panel: NSPanel?
    private var panelMoveObserver: NSObjectProtocol?
    private let panelSize = NSSize(width: 340, height: 238)

    private init() {}

    func show(model: DevAppModel, command: SwitchCommand, preferredScreen: NSScreen? = nil) {
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.contentViewController = NSHostingController(
            rootView: DevFloatingMenuPanelView(
                model: model,
                command: command,
                close: { [weak self] in
                    self?.close()
                }
            )
        )
        position(panel, for: model, preferredScreen: preferredScreen)
        panel.orderFrontRegardless()
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.identifier = DevMenuBarWindowCloser.floatingPanelIdentifier
        panelMoveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self, weak panel] _ in
            Task { @MainActor in
                guard let self, let panel else {
                    return
                }

                self.savePosition(of: panel)
            }
        }
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.collectionBehavior.insert([
            .canJoinAllSpaces,
            .fullScreenAuxiliary
        ])
        return panel
    }

    private func position(_ panel: NSPanel, for model: DevAppModel, preferredScreen: NSScreen?) {
        let screen = preferredScreen ?? targetScreen(for: model) ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else {
            panel.setFrame(NSRect(origin: CGPoint(x: 120, y: 120), size: panelSize), display: true)
            return
        }

        let frame = screen.visibleFrame
        let origin = savedOrigin(in: frame) ?? defaultOrigin(in: frame)
        panel.setFrame(NSRect(origin: origin, size: panelSize), display: true)
    }

    private func defaultOrigin(in frame: CGRect) -> CGPoint {
        CGPoint(
            x: frame.maxX - panelSize.width - 16,
            y: frame.maxY - panelSize.height - 14
        )
    }

    private func savedOrigin(in frame: CGRect) -> CGPoint? {
        guard let position = DevFloatingPanelPositionStore.load() else {
            return nil
        }

        let xRange = max(frame.width - panelSize.width, 1)
        let yRange = max(frame.height - panelSize.height, 1)
        return CGPoint(
            x: frame.minX + xRange * position.xRatio,
            y: frame.minY + yRange * position.yRatio
        )
    }

    private func savePosition(of panel: NSPanel) {
        guard let screen = screen(containing: panel.frame) ?? panel.screen else {
            return
        }

        let visibleFrame = screen.visibleFrame
        let xRange = max(visibleFrame.width - panel.frame.width, 1)
        let yRange = max(visibleFrame.height - panel.frame.height, 1)
        let xRatio = (panel.frame.minX - visibleFrame.minX) / xRange
        let yRatio = (panel.frame.minY - visibleFrame.minY) / yRange
        DevFloatingPanelPositionStore.save(DevFloatingPanelPosition(
            xRatio: min(max(xRatio, 0), 1),
            yRatio: min(max(yRatio, 0), 1)
        ))
    }

    private func screen(containing frame: CGRect) -> NSScreen? {
        NSScreen.screens
            .map { screen in
                (screen: screen, area: screen.visibleFrame.intersection(frame).area)
            }
            .filter { $0.area > 0 }
            .max { $0.area < $1.area }?
            .screen
    }

    private func targetScreen(for model: DevAppModel) -> NSScreen? {
        let selectedIDs = model.selectedDisplayIDs
        let targetStableID = model.displayLayout.displays
            .first { selectedIDs.contains($0.id) }?
            .id
        guard let targetDisplayID = targetStableID.flatMap(Self.directDisplayID(for:)) else {
            return NSScreen.main
        }

        return NSScreen.screens.first { screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            return number?.uint32Value == targetDisplayID
        }
    }

    private static func directDisplayID(for stableID: String) -> CGDirectDisplayID? {
        stableID
            .split(separator: "-")
            .last
            .flatMap { UInt32($0) }
    }
}

private struct DevFloatingPanelPosition {
    let xRatio: CGFloat
    let yRatio: CGFloat
}

private enum DevFloatingPanelPositionStore {
    private static let xKey = "sideby.dev.floating-panel.x-ratio"
    private static let yKey = "sideby.dev.floating-panel.y-ratio"

    static func load() -> DevFloatingPanelPosition? {
        guard UserDefaults.standard.object(forKey: xKey) != nil,
              UserDefaults.standard.object(forKey: yKey) != nil else {
            return nil
        }

        return DevFloatingPanelPosition(
            xRatio: CGFloat(UserDefaults.standard.double(forKey: xKey)),
            yRatio: CGFloat(UserDefaults.standard.double(forKey: yKey))
        )
    }

    static func save(_ position: DevFloatingPanelPosition) {
        UserDefaults.standard.set(Double(position.xRatio), forKey: xKey)
        UserDefaults.standard.set(Double(position.yRatio), forKey: yKey)
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isInfinite else {
            return 0
        }

        return max(width, 0) * max(height, 0)
    }
}

private struct DevFloatingMenuPanelView: View {
    @ObservedObject var model: DevAppModel
    let command: SwitchCommand
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                DevPanelDragHandle()
                    .frame(width: 16, height: 18)
                Image(systemName: "hammer")
                    .foregroundStyle(.orange)
                Text("SBS Dev")
                    .font(.headline.weight(.semibold))
                Text(command == .next ? "Next" : "Previous")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color(nsColor: .systemOrange))
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                Spacer()
                Button("Close", action: close)
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                DevMenuStatusRow(label: "Displays", value: "\(model.displayLayout.displayCount)")
                DevMenuStatusRow(label: "Targets", value: model.selectedDisplaySummary)
                DevMenuStatusRow(label: "Access", value: String(describing: model.permissionState))
                DevMenuStatusRow(label: "Last", value: model.lastSwitchResult)
            }

            HStack(spacing: 8) {
                Button("<- Previous") {
                    model.switchContextWithHiddenCursor(.previous)
                }
                Button("Next ->") {
                    model.switchContextWithHiddenCursor(.next)
                }
                Spacer()
                Button("Refresh") {
                    model.refresh()
                }
            }
        }
        .padding(14)
        .frame(width: 340, height: 238, alignment: .topLeading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
    }
}

private struct DevPanelDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DraggableHandleView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class DraggableHandleView: NSView {
    private var initialWindowOrigin = CGPoint.zero
    private var initialMouseLocation = CGPoint.zero

    override var acceptsFirstResponder: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.secondaryLabelColor.setFill()

        let dotSize: CGFloat = 2.2
        let spacing: CGFloat = 4.5
        let startX = (bounds.width - spacing) / 2
        let startY = (bounds.height - spacing) / 2

        for row in 0..<2 {
            for column in 0..<2 {
                let rect = NSRect(
                    x: startX + CGFloat(column) * spacing,
                    y: startY + CGFloat(row) * spacing,
                    width: dotSize,
                    height: dotSize
                )
                NSBezierPath(ovalIn: rect).fill()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else {
            return
        }

        initialWindowOrigin = window.frame.origin
        initialMouseLocation = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else {
            return
        }

        let currentMouseLocation = NSEvent.mouseLocation
        let delta = CGPoint(
            x: currentMouseLocation.x - initialMouseLocation.x,
            y: currentMouseLocation.y - initialMouseLocation.y
        )
        window.setFrameOrigin(CGPoint(
            x: initialWindowOrigin.x + delta.x,
            y: initialWindowOrigin.y + delta.y
        ))
    }
}

private struct DevWindowBehaviorInstaller: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configureWindow(for: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindow(for: nsView)
        }
    }

    private func configureWindow(for view: NSView) {
        guard let window = view.window else {
            return
        }

        window.identifier = DevMenuBarWindowCloser.mainWindowIdentifier
        window.collectionBehavior.insert([
            .canJoinAllSpaces,
            .fullScreenAuxiliary
        ])
    }
}

private enum DevCommandLineRunner {
    static func runIfRequested(arguments: [String] = CommandLine.arguments) -> Bool {
        if runProbeIfRequested(arguments: arguments) {
            return true
        }

        let command: SwitchCommand?
        if arguments.contains("--post-next-hidden") {
            command = .next
        } else if arguments.contains("--post-previous-hidden") {
            command = .previous
        } else {
            command = nil
        }

        guard let command else {
            return false
        }

        let permissionState = AccessibilityPermissionService().currentState
        let postEventAccess = CGPreflightPostEventAccess() || CGRequestPostEventAccess()
        let didPost = HiddenCursorDisplaySpaceCommandExecutor().execute(command)

        let message = "SidebyDevApp \(command): \(didPost ? "posted" : "failed"), accessibility: \(permissionState), postEvents: \(postEventAccess ? "granted" : "denied")"
        print(message)
        appendDebugLog(message)
        return true
    }

    private static func runProbeIfRequested(arguments: [String]) -> Bool {
        if arguments.contains("--probe-active-observer-next") {
            runActiveObserverProbe(.next)
            return true
        }

        if arguments.contains("--probe-active-observer-previous") {
            runActiveObserverProbe(.previous)
            return true
        }

        if arguments.contains("--probe-window-diff-next") {
            runWindowDiffProbe(.next)
            return true
        }

        if arguments.contains("--probe-window-diff-previous") {
            runWindowDiffProbe(.previous)
            return true
        }

        if arguments.contains("--probe-overlay-click-next") {
            runOverlayClickProbe(.next)
            return true
        }

        if arguments.contains("--probe-overlay-click-previous") {
            runOverlayClickProbe(.previous)
            return true
        }

        if arguments.contains("--probe-overlay-click-repeat") {
            runOverlayClickRepeatProbe(arguments: arguments)
            return true
        }

        if arguments.contains("--probe-key-poster-matrix") {
            runKeyPosterMatrixProbe(arguments: arguments)
            return true
        }

        if arguments.contains("--probe-key-poster-repeat") {
            runKeyPosterRepeatProbe(arguments: arguments)
            return true
        }

        if arguments.contains("--probe-acking-hidden-matrix") {
            runAckingHiddenMatrixProbe()
            return true
        }

        if arguments.contains("--probe-acking-hidden-repeat") {
            runAckingHiddenRepeatProbe(arguments: arguments)
            return true
        }

        if arguments.contains("--probe-ax-anchor") {
            runAXAnchorProbe()
            return true
        }

        if arguments.contains("--probe-ax-anchor-next") {
            runAXAnchorSwitchProbe(.next)
            return true
        }

        if arguments.contains("--probe-ax-anchor-previous") {
            runAXAnchorSwitchProbe(.previous)
            return true
        }

        if let shortcutName = argumentValue(after: "--probe-shortcut", in: arguments) {
            runShortcutProbe(shortcutName: shortcutName)
            return true
        }

        return false
    }

    private static func runActiveObserverProbe(_ command: SwitchCommand) {
        let observer = ActiveSpaceNotificationCounter()
        let before = observer.changeCount
        let didPost = HiddenCursorDisplaySpaceCommandExecutor().execute(command)
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        let observation = ActiveSpaceSwitchObservation(
            command: command,
            didExecuteCommand: didPost,
            beforeChangeCount: before,
            afterChangeCount: observer.changeCount
        )
        printAndLog("ActiveObserverProbe: \(observation.summary)")
    }

    private static func runWindowDiffProbe(_ command: SwitchCommand) {
        let provider = CGWindowListSnapshotProvider()
        let before = provider.snapshot()
        let didPost = HiddenCursorDisplaySpaceCommandExecutor().execute(command)
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        let after = provider.snapshot()
        let diff = WindowListDiffResult(before: before, after: after)
        printAndLog("WindowDiffProbe \(command) \(didPost ? "posted" : "failed"): \(diff.summary)")
    }

    private static func runOverlayClickProbe(_ command: SwitchCommand) {
        let result = executeOverlayClickProbe(command)
        printAndLog("OverlayClickProbe: \(result.summary)")
    }

    private static func runOverlayClickRepeatProbe(arguments: [String]) {
        let focusDelay = doubleArgument(after: "--focus", in: arguments) ?? 0.05
        let switchDelay = doubleArgument(after: "--switch", in: arguments) ?? HiddenSwitchTimingConfiguration.optimizedCandidate.switchDelay
        let count = intArgument(after: "--count", in: arguments) ?? 3
        let timing = HiddenSwitchTimingConfiguration(
            focusDelay: focusDelay,
            switchDelay: switchDelay,
            observerWait: 0.85
        )

        printAndLog("OverlayClickRepeat: start count=\(count) \(timing.summary)")
        var nextConfirmed = 0
        var previousConfirmed = 0
        var totalRoundTripElapsed: TimeInterval = 0

        for index in 1...max(1, count) {
            let next = executeOverlayClickProbe(.next, timing: timing)
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            let previous = executeOverlayClickProbe(.previous, timing: timing)
            if next.isAckConfirmedSuccess {
                nextConfirmed += 1
            }
            if previous.isAckConfirmedSuccess {
                previousConfirmed += 1
            }
            totalRoundTripElapsed += next.elapsedSeconds + previous.elapsedSeconds
            printAndLog("OverlayClickRepeatRun \(index): \(next.summary) | \(previous.summary)")
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        }

        let runCount = max(1, count)
        printAndLog(
            "OverlayClickRepeatSummary: \(timing.summary), nextConfirmed=\(nextConfirmed)/\(runCount), previousConfirmed=\(previousConfirmed)/\(runCount), avgRoundTripElapsed=\(String(format: "%.2f", totalRoundTripElapsed / Double(runCount)))s"
        )
    }

    private static func executeOverlayClickProbe(
        _ command: SwitchCommand,
        timing: HiddenSwitchTimingConfiguration = .optimizedCandidate
    ) -> AckingHiddenSwitchProbeResult {
        let targetProvider = CGDisplaySwitchTargetProvider()
        let executor = OverlayClickDisplaySpaceCommandExecutor(
            targetProvider: targetProvider,
            clickDelay: timing.focusDelay,
            switchDelay: timing.switchDelay
        )
        let runner = AckingHiddenSpaceCommandRunner(
            executor: executor,
            targetProvider: targetProvider,
            activeSpaceObserver: NSWorkspaceActiveSpaceChangeObserver(),
            windowSnapshotProvider: CGWindowListSnapshotProvider(),
            timing: timing
        )
        return runner.executeWithDiagnostics(command)
    }

    private static func runKeyPosterMatrixProbe(arguments: [String]) {
        let count = intArgument(after: "--count", in: arguments) ?? 3
        printAndLog("KeyPosterMatrix: start count=\(count), variants=\(KeyPosterProbeVariant.allCases.map(\.rawValue).joined(separator: ","))")

        for variant in KeyPosterProbeVariant.allCases {
            runKeyPosterRepeatProbe(variant: variant, count: count)
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
    }

    private static func runKeyPosterRepeatProbe(arguments: [String]) {
        let variant = argumentValue(after: "--poster", in: arguments)
            .flatMap(KeyPosterProbeVariant.init(rawValue:)) ?? .appleScript
        let count = intArgument(after: "--count", in: arguments) ?? 3
        runKeyPosterRepeatProbe(variant: variant, count: count)
    }

    private static func runKeyPosterRepeatProbe(variant: KeyPosterProbeVariant, count: Int) {
        let timing = HiddenSwitchTimingConfiguration.optimizedCandidate
        printAndLog("KeyPosterRepeat[\(variant.rawValue)]: start count=\(count) \(timing.summary)")
        var nextConfirmed = 0
        var previousConfirmed = 0
        var totalRoundTripElapsed: TimeInterval = 0

        for index in 1...max(1, count) {
            let next = executeKeyPosterProbe(.next, variant: variant, timing: timing)
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            let previous = executeKeyPosterProbe(.previous, variant: variant, timing: timing)
            if next.isAckConfirmedSuccess {
                nextConfirmed += 1
            }
            if previous.isAckConfirmedSuccess {
                previousConfirmed += 1
            }
            totalRoundTripElapsed += next.elapsedSeconds + previous.elapsedSeconds
            printAndLog("KeyPosterRepeatRun[\(variant.rawValue)] \(index): \(next.summary) | \(previous.summary)")
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        }

        let runCount = max(1, count)
        printAndLog(
            "KeyPosterRepeatSummary[\(variant.rawValue)]: \(timing.summary), nextConfirmed=\(nextConfirmed)/\(runCount), previousConfirmed=\(previousConfirmed)/\(runCount), avgRoundTripElapsed=\(String(format: "%.2f", totalRoundTripElapsed / Double(runCount)))s"
        )
    }

    private static func executeKeyPosterProbe(
        _ command: SwitchCommand,
        variant: KeyPosterProbeVariant,
        timing: HiddenSwitchTimingConfiguration
    ) -> AckingHiddenSwitchProbeResult {
        let targetProvider = CGDisplaySwitchTargetProvider()
        let executor = HiddenCursorDisplaySpaceCommandExecutor(
            baseExecutor: variant.baseExecutor(),
            targetProvider: targetProvider,
            focusDelay: timing.focusDelay,
            switchDelay: timing.switchDelay
        )
        let runner = AckingHiddenSpaceCommandRunner(
            executor: executor,
            targetProvider: targetProvider,
            activeSpaceObserver: NSWorkspaceActiveSpaceChangeObserver(),
            windowSnapshotProvider: CGWindowListSnapshotProvider(),
            timing: timing
        )
        return runner.executeWithDiagnostics(command)
    }

    private static func runAckingHiddenMatrixProbe() {
        let focusDelays: [TimeInterval] = [0.01, 0.02, 0.04, 0.08, 0.12]
        let switchDelays: [TimeInterval] = [0.12, 0.18, 0.20, 0.21, 0.22, 0.24, 0.32, 0.45, 0.60]
        let timings = focusDelays.flatMap { focusDelay in
            switchDelays.map { switchDelay in
                HiddenSwitchTimingConfiguration(
                    focusDelay: focusDelay,
                    switchDelay: switchDelay,
                    observerWait: 0.85
                )
            }
        }

        printAndLog("AckingHiddenMatrix: start configs=\(timings.count)")
        var pairs: [(timing: HiddenSwitchTimingConfiguration, next: AckingHiddenSwitchProbeResult, previous: AckingHiddenSwitchProbeResult)] = []

        for timing in timings {
            let next = runAckingHiddenProbe(.next, timing: timing)
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            let previous = runAckingHiddenProbe(.previous, timing: timing)
            pairs.append((timing, next, previous))
            printAndLog("AckingHiddenMatrixPair: \(next.summary) | \(previous.summary)")
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        }

        let confirmedPairs = pairs.filter { $0.next.isAckConfirmedSuccess && $0.previous.isAckConfirmedSuccess }
        let best = confirmedPairs.min { lhs, rhs in
            let lhsDuration = lhs.next.elapsedSeconds + lhs.previous.elapsedSeconds
            let rhsDuration = rhs.next.elapsedSeconds + rhs.previous.elapsedSeconds
            if lhsDuration != rhsDuration {
                return lhsDuration < rhsDuration
            }

            let lhsEstimated = lhs.timing.estimatedExecutorDuration(displayCount: lhs.next.displayTargetCount)
            let rhsEstimated = rhs.timing.estimatedExecutorDuration(displayCount: rhs.next.displayTargetCount)
            return lhsEstimated < rhsEstimated
        }

        if let best {
            let totalElapsed = best.next.elapsedSeconds + best.previous.elapsedSeconds
            printAndLog(
                "AckingHiddenMatrixBest: \(best.timing.summary), confirmedPairs=\(confirmedPairs.count)/\(pairs.count), roundTripElapsed=\(String(format: "%.2f", totalElapsed))s"
            )
        } else {
            printAndLog("AckingHiddenMatrixBest: none, confirmedPairs=0/\(pairs.count)")
        }
    }

    private static func runAckingHiddenRepeatProbe(arguments: [String]) {
        let focusDelay = doubleArgument(after: "--focus", in: arguments) ?? HiddenSwitchTimingConfiguration.optimizedCandidate.focusDelay
        let switchDelay = doubleArgument(after: "--switch", in: arguments) ?? HiddenSwitchTimingConfiguration.optimizedCandidate.switchDelay
        let hideSettleDelay = doubleArgument(after: "--hide-settle", in: arguments) ?? HiddenSwitchTimingConfiguration.optimizedCandidate.hideSettleDelay
        let transitionSettleDelay = doubleArgument(after: "--transition-settle", in: arguments) ?? HiddenSwitchTimingConfiguration.optimizedCandidate.transitionSettleDelay
        let restoreDelay = doubleArgument(after: "--restore", in: arguments) ?? HiddenSwitchTimingConfiguration.optimizedCandidate.restoreDelay
        let count = intArgument(after: "--count", in: arguments) ?? 5
        let timing = HiddenSwitchTimingConfiguration(
            hideSettleDelay: hideSettleDelay,
            focusDelay: focusDelay,
            switchDelay: switchDelay,
            transitionSettleDelay: transitionSettleDelay,
            restoreDelay: restoreDelay,
            observerWait: 0.85
        )

        printAndLog("AckingHiddenRepeat: start count=\(count) \(timing.summary)")
        var nextConfirmed = 0
        var previousConfirmed = 0
        var totalRoundTripElapsed: TimeInterval = 0

        for index in 1...max(1, count) {
            let next = runAckingHiddenProbe(.next, timing: timing)
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            let previous = runAckingHiddenProbe(.previous, timing: timing)
            if next.isAckConfirmedSuccess {
                nextConfirmed += 1
            }
            if previous.isAckConfirmedSuccess {
                previousConfirmed += 1
            }
            totalRoundTripElapsed += next.elapsedSeconds + previous.elapsedSeconds
            printAndLog("AckingHiddenRepeatRun \(index): \(next.summary) | \(previous.summary)")
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        }

        let runCount = max(1, count)
        printAndLog(
            "AckingHiddenRepeatSummary: \(timing.summary), nextConfirmed=\(nextConfirmed)/\(runCount), previousConfirmed=\(previousConfirmed)/\(runCount), avgRoundTripElapsed=\(String(format: "%.2f", totalRoundTripElapsed / Double(runCount)))s"
        )
    }

    private static func runAckingHiddenProbe(
        _ command: SwitchCommand,
        timing: HiddenSwitchTimingConfiguration
    ) -> AckingHiddenSwitchProbeResult {
        let targetProvider = CGDisplaySwitchTargetProvider()
        let runner = AckingHiddenSpaceCommandRunner(
            timing: timing,
            targetProvider: targetProvider
        )
        return runner.executeWithDiagnostics(command)
    }

    private static func runAXAnchorProbe() {
        let results = AXFocusAnchorProbe().probeTargets(performRaise: true)
        let summary = results.isEmpty
            ? "no display target points"
            : results.map(\.summary).joined(separator: " | ")
        printAndLog("AXAnchorProbe: \(summary)")
    }

    private static func runAXAnchorSwitchProbe(_ command: SwitchCommand) {
        let observer = ActiveSpaceNotificationCounter()
        let before = observer.changeCount
        let didPost = AXFocusAnchorDisplaySpaceCommandExecutor().execute(command)
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        let observation = ActiveSpaceSwitchObservation(
            command: command,
            didExecuteCommand: didPost,
            beforeChangeCount: before,
            afterChangeCount: observer.changeCount
        )
        printAndLog("AXAnchorSwitchProbe: \(observation.summary)")
    }

    private static func runShortcutProbe(shortcutName: String) {
        let probe = ShortcutsCommandLineProbe()
        let preflight = probe.preflight(shortcutName: shortcutName)
        let summary: String
        if preflight.exactMatchExists {
            let result = probe.runShortcut(named: shortcutName)
            summary = "run \(result.summary)"
        } else {
            summary = preflight.summary
        }
        printAndLog("ShortcutsProbe: \(summary)")
    }

    private static func argumentValue(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag) else {
            return nil
        }

        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else {
            return nil
        }

        return arguments[valueIndex]
    }

    private static func doubleArgument(after flag: String, in arguments: [String]) -> Double? {
        argumentValue(after: flag, in: arguments).flatMap(Double.init)
    }

    private static func intArgument(after flag: String, in arguments: [String]) -> Int? {
        argumentValue(after: flag, in: arguments).flatMap(Int.init)
    }

    private enum KeyPosterProbeVariant: String, CaseIterable {
        case appleScript = "applescript"
        case cgHID = "cg-hid"
        case cgHIDPrivate = "cg-hid-private"
        case cgHIDNoSource = "cg-hid-nosource"
        case cgSession = "cg-session"
        case cgAnnotatedSession = "cg-annotated-session"

        func baseExecutor() -> any SpaceCommandExecuting {
            switch self {
            case .appleScript:
                MacSpaceCommandExecutor(poster: AppleScriptKeyEventPoster())
            case .cgHID:
                MacSpaceCommandExecutor(
                    poster: CGEventKeyEventPoster(
                        tap: .cghidEventTap,
                        sourceStateID: .hidSystemState
                    )
                )
            case .cgHIDPrivate:
                MacSpaceCommandExecutor(
                    poster: CGEventKeyEventPoster(
                        tap: .cghidEventTap,
                        sourceStateID: .privateState
                    )
                )
            case .cgHIDNoSource:
                MacSpaceCommandExecutor(
                    poster: CGEventKeyEventPoster(
                        tap: .cghidEventTap,
                        sourceStateID: nil
                    )
                )
            case .cgSession:
                MacSpaceCommandExecutor(
                    poster: CGEventKeyEventPoster(
                        tap: .cgSessionEventTap,
                        sourceStateID: .combinedSessionState
                    )
                )
            case .cgAnnotatedSession:
                MacSpaceCommandExecutor(
                    poster: CGEventKeyEventPoster(
                        tap: .cgAnnotatedSessionEventTap,
                        sourceStateID: .combinedSessionState
                    )
                )
            }
        }
    }

    private static func appendDebugLog(_ message: String) {
        let line = "\(Date()) \(message)\n"
        let url = URL(fileURLWithPath: "/tmp/sideby-dev-command.log")
        guard let data = line.data(using: .utf8) else {
            return
        }

        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            defer {
                try? handle.close()
            }
            do {
                _ = try handle.seekToEnd()
            } catch {
                return
            }
            handle.write(data)
        } else {
            try? data.write(to: url)
        }
    }

    private static func printAndLog(_ message: String) {
        print(message)
        appendDebugLog(message)
    }
}

private final class ActiveSpaceNotificationCounter: @unchecked Sendable {
    private var observer: NSObjectProtocol?
    private(set) var changeCount = 0

    init() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.changeCount += 1
        }
    }

    deinit {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}

@MainActor
private final class DevAppModel: ObservableObject {
    @Published var settings = AppSettings.default
    @Published var displayLayout = DisplayLayout(displays: [])
    @Published var permissionState: PermissionState = .notDetermined
    @Published var postEventAccessGranted = false
    @Published var availableSpaceCount = 3
    @Published var diagnostics: [DiagnosticState] = []
    @Published var hudState: HUDPresentationState?
    @Published var lastSwitchResult = "No switch attempted"
    @Published var activeSpaceChangeCount = 0
    @Published var lastActiveSpaceChange = "No notification observed"
    @Published var selectedDisplayIDs: Set<String> = []
    @Published var isSwipeInputListening = false
    @Published var swipeInputStatus = "Input stopped"
    @Published var swipeLastEvent = "Use the configured swipe gesture."
    let bundleIdentifier = Bundle.main.bundleIdentifier ?? "unknown"
    let bundlePath = Bundle.main.bundlePath

    private let permissionService = AccessibilityPermissionService()
    private let displayObserver = MacDisplayObserver()
    private let settingsStore = UserDefaultsSettingsStore()
    private let hudPresenter = HUDPresenter()
    private var activeSpaceObserver: NSObjectProtocol?
    private var didInitializeSelectedDisplays = false
    private var swipeInputSource: GlobalEventTapInputSource?
    private var keyboardShortcutInputSource: GlobalShortcutInputSource?
    private var swipePipeline = SwipeInputPipeline(settings: .default)
    private var isInputSwitching = false
    private var pendingInputCommand: LatchedInputCommand?
    private var settingsObserver: NSObjectProtocol?

    init() {
        var loadedSettings = settingsStore.load()
        loadedSettings.mode = .shortcut
        settings = loadedSettings
        swipeLastEvent = inputHintSummary
        startSettingsChangeObserver()
        startActiveSpaceObserver()
        refresh()
    }

    var runtimeState: RuntimeState {
        RuntimeState(
            accessibilityPermission: permissionState,
            displayLayout: displayLayout,
            availableSpaceCount: availableSpaceCount
        )
    }

    var selectedDisplaySummary: String {
        let selectedCount = selectedDisplayIDs.count
        let displayCount = displayLayout.displayCount

        if displayCount == 0 {
            return "No displays"
        }
        if selectedCount == 0 {
            return "No displays selected"
        }
        if selectedCount == displayCount {
            return "All \(displayCount) displays"
        }
        return "\(selectedCount)/\(displayCount) displays selected"
    }

    var gestureInputSummary: String {
        "\(KeyboardShortcutFormatter.modifierText(settings.requiredModifiers)) + horizontal scroll"
    }

    var keyboardCommandSummary: String {
        settings.keyboardShortcutsEnabled
            ? "\(KeyboardShortcutFormatter.shortcutText(settings.shortcutPrevious)) / \(KeyboardShortcutFormatter.shortcutText(settings.shortcutNext))"
            : "Keyboard shortcuts off"
    }

    var inputHintSummary: String {
        settings.keyboardShortcutsEnabled
            ? "Use \(gestureInputSummary), or \(keyboardCommandSummary)."
            : "Use \(gestureInputSummary)."
    }

    var keyboardShortcutModifierSummary: String {
        KeyboardShortcutFormatter.modifierText(keyboardShortcutModifiers)
    }

    func refresh() {
        displayLayout = displayObserver.currentLayout()
        syncSelectedDisplays(with: displayLayout)
        permissionState = permissionService.currentState
        postEventAccessGranted = CGPreflightPostEventAccess()
        diagnostics = DiagnosticRule.evaluate(
            decision: ModePolicy().decision(
                for: settings.mode,
                inputMethod: settings.mode == .swipe ? .swipe : .shortcut,
                runtimeState: runtimeState
            )
        )
    }

    func openSystemSettings() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    func setDisplayTarget(_ display: DisplayInfo, isSelected: Bool) {
        var selected = selectedDisplayIDs
        if isSelected {
            selected.insert(display.id)
        } else {
            selected.remove(display.id)
        }
        selectedDisplayIDs = selected
    }

    func selectAllDisplayTargets() {
        selectedDisplayIDs = Set(displayLayout.displays.map(\.id))
    }

    func updateSettings(_ newSettings: AppSettings) {
        let issues = KeyboardShortcutValidator.issues(
            previous: newSettings.shortcutPrevious,
            next: newSettings.shortcutNext,
            gestureModifiers: newSettings.requiredModifiers
        )
        guard issues.isEmpty else {
            swipeLastEvent = "Shortcut settings were not saved"
            return
        }

        var savedSettings = newSettings
        savedSettings.mode = .shortcut
        settings = savedSettings
        settingsStore.save(savedSettings)
        swipePipeline = SwipeInputPipeline(settings: currentGestureSettings)
        swipeLastEvent = "Input settings saved: \(gestureInputSummary), \(keyboardCommandSummary)"

        guard isSwipeInputListening else {
            refresh()
            return
        }

        stopSwipeInputListener()
        startSwipeInputListener()
    }

    private func startSettingsChangeObserver() {
        settingsObserver = DistributedNotificationCenter.default().addObserver(
            forName: UserDefaultsSettingsStore.settingsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reloadSettingsFromStoreIfChanged()
            }
        }
    }

    private func reloadSettingsFromStoreIfChanged() {
        var loadedSettings = settingsStore.load()
        loadedSettings.mode = .shortcut
        guard loadedSettings != settings else {
            return
        }

        settings = loadedSettings
        swipePipeline = SwipeInputPipeline(settings: currentGestureSettings)
        swipeLastEvent = "Input settings updated: \(gestureInputSummary), \(keyboardCommandSummary)"

        guard isSwipeInputListening else {
            refresh()
            return
        }

        stopSwipeInputListener()
        startSwipeInputListener()
    }

    func toggleSwipeInputListener() {
        if isSwipeInputListening {
            stopSwipeInputListener()
        } else {
            startSwipeInputListener()
        }
    }

    func startSwipeInputListener() {
        permissionService.requestAccessPrompt()
        _ = CGRequestPostEventAccess()
        refresh()
        swipePipeline = SwipeInputPipeline(settings: currentGestureSettings)

        isInputSwitching = false
        pendingInputCommand = nil
        let source = GlobalEventTapInputSource(
            suppressedScrollModifiers: settings.requiredModifiers,
            suppressedModifierFlags: nil
        ) { [weak self] event in
            DispatchQueue.main.async { [weak self] in
                self?.handleSwipeInput(event)
            }
        }
        let shortcutSource: GlobalShortcutInputSource?
        if settings.keyboardShortcutsEnabled {
            shortcutSource = GlobalShortcutInputSource(
                shortcutInputSource: ShortcutInputSource(
                    previousShortcut: settings.shortcutPrevious,
                    nextShortcut: settings.shortcutNext
                ),
                suppressedModifierFlags: nil,
                commandHandler: { [weak self] command in
                    DispatchQueue.main.async { [weak self] in
                        self?.handleKeyboardShortcutCommand(command)
                    }
                },
                releaseHandler: { [weak self] command in
                    DispatchQueue.main.async { [weak self] in
                        self?.handleKeyboardShortcutRelease(command)
                    }
                }
            )
        } else {
            shortcutSource = nil
        }

        let swipeStart = source.start()
        let didStartSwipe = Self.didStartInputSource(swipeStart)
        let didStartShortcut = shortcutSource.map { Self.didStartInputSource($0.start()) } ?? true

        guard didStartSwipe && didStartShortcut else {
            source.stop()
            shortcutSource?.stop()
            swipeInputSource = nil
            keyboardShortcutInputSource = nil
            pendingInputCommand = nil
            isSwipeInputListening = false
            swipeInputStatus = "Input failed; grant Accessibility and try again"
            if !didStartSwipe {
                swipeLastEvent = "Swipe listener failed to start"
            } else if !didStartShortcut {
                swipeLastEvent = "Keyboard command listener failed to start"
            }
            refresh()
            return
        }

        swipeInputSource = source
        keyboardShortcutInputSource = shortcutSource
        isSwipeInputListening = true
        swipeInputStatus = "Input listening; targets \(selectedDisplaySummary)"
        refresh()
    }

    func stopSwipeInputListener() {
        swipeInputSource?.stop()
        swipeInputSource = nil
        keyboardShortcutInputSource?.stop()
        keyboardShortcutInputSource = nil
        isInputSwitching = false
        pendingInputCommand = nil
        isSwipeInputListening = false
        swipeInputStatus = "Input stopped"
    }

    private static func didStartInputSource(_ result: GlobalEventTapStartResult) -> Bool {
        switch result {
        case .started, .alreadyRunning:
            return true
        case .failedToCreateTap:
            return false
        }
    }

    @discardableResult
    func switchContextWithHiddenCursor(
        _ command: SwitchCommand,
        preferredFloatingScreen: NSScreen? = nil
    ) -> Bool {
        _ = CGRequestPostEventAccess()
        refresh()
        guard hasSelectedMoveTargets(command: command, label: "hidden") else {
            return false
        }

        lastSwitchResult = "Queued hidden \(command): \(selectedDisplaySummary)"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else {
                return
            }

            let result = self.performSwitchContext(
                command,
                executor: self.hiddenExecutorForSelectedDisplays(),
                label: "hidden"
            )
            if result.didExecute {
                self.showFloatingDevPanel(
                    command: command,
                    preferredScreen: preferredFloatingScreen
                )
            }
        }
        return true
    }

    @discardableResult
    private func performSwitchContext<Executor: SpaceCommandExecuting>(
        _ command: SwitchCommand,
        executor: Executor,
        label: String?,
        inputMethod: InputMethod = .shortcut
    ) -> ContextSwitchResult {
        let engine = ContextSwitchEngine(executor: executor)
        let result = engine.switchContext(
            command,
            mode: settings.mode,
            inputMethod: inputMethod,
            runtimeState: runtimeState
        )

        diagnostics = result.diagnostics
        let commandLabel = label.map { "\($0) \(command)" } ?? "\(command)"
        lastSwitchResult = result.didExecute ? "Posted \(commandLabel)" : "Blocked \(commandLabel)"
        hudState = result.didExecute
            ? hudPresenter.state(for: command)
            : result.diagnostics.first.map { hudPresenter.state(for: $0) }
        return result
    }

    private func showFloatingDevPanel(command: SwitchCommand, preferredScreen: NSScreen? = nil) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else {
                return
            }

            DevMenuBarWindowCloser.closeTransientMenuWindows()
            DevFloatingMenuPanelController.shared.show(
                model: self,
                command: command,
                preferredScreen: preferredScreen
            )
        }
    }

    private func hasSelectedMoveTargets(command: SwitchCommand, label: String) -> Bool {
        guard !selectedDisplayIDs.isEmpty else {
            let diagnostic = DiagnosticState(
                severity: .blocker,
                title: "No move targets selected",
                message: "Select at least one display before running Previous or Next.",
                actionLabel: nil
            )
            diagnostics = [diagnostic]
            hudState = hudPresenter.state(for: diagnostic)
            lastSwitchResult = "Blocked \(label) \(command): no move targets"
            return false
        }

        return true
    }

    private var currentGestureSettings: GestureSettings {
        GestureSettings(
            requiredModifiers: settings.requiredModifiers,
            horizontalThreshold: settings.horizontalThreshold,
            dominanceRatio: 1.4,
            ignoresMomentum: true,
            naturalScrollingEnabled: true
        )
    }

    private var keyboardShortcutModifiers: ModifierFlags {
        settings.shortcutPrevious.modifiers.union(settings.shortcutNext.modifiers)
    }

    private func handleSwipeInput(_ event: InputEvent) {
        let event = eventWithCurrentModifierState(event)
        switch event.type {
        case .scrollWheel:
            guard !isInputSwitching, pendingInputCommand == nil else {
                return
            }
            swipeLastEvent = "Scroll dx=\(Int(event.deltaX)) dy=\(Int(event.deltaY)) modifiers=\(modifierSummary(event.modifierFlags))"
        case .flagsChanged:
            if let latchedCommand = releasedPendingInputCommand(for: event) {
                switch latchedCommand.source {
                case .swipe:
                    executeSwipeCommand(latchedCommand.command)
                case .keyboard:
                    executeKeyboardCommand(latchedCommand.command)
                }
                return
            }
            guard !isInputSwitching, pendingInputCommand == nil else {
                return
            }
            swipeLastEvent = "Modifiers \(modifierSummary(event.modifierFlags))"
            return
        default:
            guard !isInputSwitching, pendingInputCommand == nil else {
                return
            }
            break
        }

        guard let command = swipePipeline.command(for: event) else {
            return
        }

        guard !selectedDisplayIDs.isEmpty else {
            lastSwitchResult = "Blocked modifier-swipe \(command): no display targets"
            swipeInputStatus = "Input listening; no move targets selected"
            return
        }

        pendingInputCommand = LatchedInputCommand(command: command, source: .swipe)
        swipeLastEvent = "Accepted \(command); release \(KeyboardShortcutFormatter.modifierText(settings.requiredModifiers))"
        swipeInputStatus = "Release gesture modifier to switch"
    }

    private func eventWithCurrentModifierState(_ event: InputEvent) -> InputEvent {
        guard event.type == .scrollWheel else {
            return event
        }

        let currentModifiers = EventTapInputNormalizer.modifierFlags(
            from: CGEventSource.flagsState(.combinedSessionState)
        )
        let effectiveModifiers = InputModifierStateCombiner.effectiveModifiers(
            eventModifiers: event.modifierFlags,
            currentModifiers: currentModifiers
        )
        return event.replacingModifierFlags(effectiveModifiers)
    }

    private func executeSwipeCommand(_ command: SwitchCommand) {
        guard !selectedDisplayIDs.isEmpty else {
            lastSwitchResult = "Blocked modifier-swipe \(command): no display targets"
            swipeInputStatus = "Input listening; no move targets selected"
            pendingInputCommand = nil
            return
        }

        isInputSwitching = true
        pendingInputCommand = nil
        swipeLastEvent = "Switching \(command) from \(KeyboardShortcutFormatter.modifierText(settings.requiredModifiers)) swipe; targets=\(selectedDisplaySummary)"
        let result = performSwitchContext(
            command,
            executor: hiddenExecutorForSelectedDisplays(),
            label: "modifier-swipe",
            inputMethod: .swipe
        )
        if result.didExecute {
            showFloatingDevPanel(command: command)
        }
        swipeInputStatus = "Input listening; targets \(selectedDisplaySummary)"
        finishInputSwitchCooldown()
    }

    private func handleKeyboardShortcutCommand(_ command: SwitchCommand) {
        guard !isInputSwitching, pendingInputCommand == nil else {
            return
        }
        guard !selectedDisplayIDs.isEmpty else {
            lastSwitchResult = "Blocked keyboard-command \(command): no display targets"
            swipeInputStatus = "Input listening; no move targets selected"
            return
        }

        pendingInputCommand = LatchedInputCommand(command: command, source: .keyboard)
        swipeLastEvent = "Accepted \(command); release \(KeyboardShortcutFormatter.modifierText(shortcutModifiers(for: command)))"
        swipeInputStatus = "Release shortcut modifier to switch"
    }

    private func handleKeyboardShortcutRelease(_ command: SwitchCommand) {
        waitForKeyboardShortcutModifiersToRelease(
            command: command,
            modifiers: shortcutModifiers(for: command)
        )
    }

    private func waitForKeyboardShortcutModifiersToRelease(
        command: SwitchCommand,
        modifiers: ModifierFlags,
        remainingAttempts: Int = 40
    ) {
        guard remainingAttempts > 0 else {
            return
        }

        let currentModifiers = EventTapInputNormalizer.modifierFlags(
            from: CGEventSource.flagsState(.combinedSessionState)
        )
        guard currentModifiers.contains(modifiers) else {
            guard let latchedCommand = pendingInputCommand,
                  latchedCommand.source == .keyboard,
                  latchedCommand.command == command
            else {
                return
            }

            pendingInputCommand = nil
            executeKeyboardCommand(command)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) { [weak self] in
            self?.waitForKeyboardShortcutModifiersToRelease(
                command: command,
                modifiers: modifiers,
                remainingAttempts: remainingAttempts - 1
            )
        }
    }

    private func executeKeyboardCommand(_ command: SwitchCommand) {
        guard !selectedDisplayIDs.isEmpty else {
            lastSwitchResult = "Blocked keyboard-command \(command): no display targets"
            swipeInputStatus = "Input listening; no move targets selected"
            pendingInputCommand = nil
            return
        }

        isInputSwitching = true
        pendingInputCommand = nil
        swipeLastEvent = "Switching \(command) from \(keyboardShortcutModifierSummary) shortcut; targets=\(selectedDisplaySummary)"
        let result = performSwitchContext(
            command,
            executor: hiddenExecutorForSelectedDisplays(),
            label: "keyboard-command",
            inputMethod: .shortcut
        )
        if result.didExecute {
            showFloatingDevPanel(command: command)
        }
        swipeInputStatus = "Input listening; targets \(selectedDisplaySummary)"
        finishInputSwitchCooldown()
    }

    private func releasedPendingInputCommand(for event: InputEvent) -> LatchedInputCommand? {
        guard let latchedCommand = pendingInputCommand else {
            return nil
        }

        let releaseModifiers: ModifierFlags
        switch latchedCommand.source {
        case .swipe:
            releaseModifiers = settings.requiredModifiers
        case .keyboard:
            releaseModifiers = shortcutModifiers(for: latchedCommand.command)
        }

        guard InputModifierReleasePolicy.didReleaseAllTriggerModifiers(
            currentModifiers: event.modifierFlags,
            triggerModifiers: releaseModifiers
        ) else {
            return nil
        }

        pendingInputCommand = nil
        return latchedCommand
    }

    private func finishInputSwitchCooldown() {
        DispatchQueue.main.asyncAfter(deadline: .now() + InputCommandLatch.defaultCooldownInterval) { [weak self] in
            self?.isInputSwitching = false
        }
    }

    private func modifierSummary(_ modifiers: ModifierFlags) -> String {
        var names: [String] = []
        if modifiers.contains(.shift) {
            names.append("shift")
        }
        if modifiers.contains(.control) {
            names.append("control")
        }
        if modifiers.contains(.option) {
            names.append("option")
        }
        if modifiers.contains(.command) {
            names.append("command")
        }
        if modifiers.contains(.function) {
            names.append("function")
        }
        return names.isEmpty ? "none" : names.joined(separator: "+")
    }

    private func syncSelectedDisplays(with layout: DisplayLayout) {
        let currentIDs = Set(layout.displays.map(\.id))
        if !didInitializeSelectedDisplays {
            selectedDisplayIDs = currentIDs
            didInitializeSelectedDisplays = true
        } else {
            selectedDisplayIDs = selectedDisplayIDs.intersection(currentIDs)
        }
    }

    private func selectedTargetProvider() -> CGDisplaySwitchTargetProvider {
        CGDisplaySwitchTargetProvider(includedStableIDs: selectedDisplayIDs)
    }

    private func hiddenExecutorForSelectedDisplays() -> HiddenCursorDisplaySpaceCommandExecutor {
        return HiddenCursorDisplaySpaceCommandExecutor(
            baseExecutor: MacSpaceCommandExecutor(poster: AppleScriptKeyEventPoster()),
            targetProvider: selectedTargetProvider()
        )
    }

    private func shortcutModifiers(for command: SwitchCommand) -> ModifierFlags {
        switch command {
        case .previous:
            settings.shortcutPrevious.modifiers
        case .next:
            settings.shortcutNext.modifiers
        }
    }

    private func startActiveSpaceObserver() {
        activeSpaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let eventSummary = "\(Date()) object=\(type(of: notification.object as Any)) userInfo=\(notification.userInfo == nil ? "none" : "present")"

            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                self.activeSpaceChangeCount += 1
                self.lastActiveSpaceChange = eventSummary
            }
        }
    }

}

private struct DevAppView: View {
    @ObservedObject var model: DevAppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerSection
                v1ScreenSwitchSection
                moveTargetsSection
                inputSection
                statusSection
                diagnosticsSection
                hudSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Sideby")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Refresh") {
                    model.refresh()
                }
            }

            Text("\(model.displayLayout.displayCount) displays detected")
                .foregroundStyle(.secondary)
        }
    }

    private var statusSection: some View {
        GroupBox("Status") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Displays")
                    Text("\(model.displayLayout.displayCount)")
                        .foregroundStyle(.secondary)
                }
                GridRow {
                    Text("External")
                    Text(model.displayLayout.hasExternalDisplay ? "Yes" : "No")
                        .foregroundStyle(.secondary)
                }
                GridRow {
                    Text("Accessibility")
                    Text(String(describing: model.permissionState))
                        .foregroundStyle(.secondary)
                }
                GridRow {
                    Text("Post Events")
                    Text(model.postEventAccessGranted ? "granted" : "denied")
                        .foregroundStyle(.secondary)
                }
                GridRow {
                    Text("Bundle ID")
                    Text(model.bundleIdentifier)
                        .foregroundStyle(.secondary)
                }
                GridRow {
                    Text("Bundle Path")
                    Text(model.bundlePath)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                GridRow {
                    Text("Last switch")
                    Text(model.lastSwitchResult)
                        .foregroundStyle(.secondary)
                }
                GridRow {
                    Text("Active Space events")
                    Text("\(model.activeSpaceChangeCount)")
                        .foregroundStyle(.secondary)
                }
                GridRow {
                    Text("Last Space event")
                    Text(model.lastActiveSpaceChange)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var v1ScreenSwitchSection: some View {
        GroupBox("Screen Switching") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button("<- Previous") {
                        model.switchContextWithHiddenCursor(.previous)
                    }
                    Button("Next ->") {
                        model.switchContextWithHiddenCursor(.next)
                    }
                }

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        Text("Targets")
                        Text(model.selectedDisplaySummary)
                            .foregroundStyle(.secondary)
                    }
                    GridRow {
                        Text("Last switch")
                        Text(model.lastSwitchResult)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var moveTargetsSection: some View {
        GroupBox("Move Targets") {
            VStack(alignment: .leading, spacing: 10) {
                if model.displayLayout.displays.isEmpty {
                    Text("No displays")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.displayLayout.displays, id: \.id) { display in
                        Toggle(
                            displayTargetTitle(display),
                            isOn: Binding(
                                get: { model.selectedDisplayIDs.contains(display.id) },
                                set: { model.setDisplayTarget(display, isSelected: $0) }
                            )
                        )
                        .help(display.id)
                    }
                }

                HStack(spacing: 10) {
                    Button("All Displays") {
                        model.selectAllDisplayTargets()
                    }
                    Text(model.selectedDisplaySummary)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var inputSection: some View {
        GroupBox("Input") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button(model.isSwipeInputListening ? "Stop Listening" : "Start Listening") {
                        model.toggleSwipeInputListener()
                    }
                    Text(model.swipeInputStatus)
                        .foregroundStyle(.secondary)
                }

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        Text("Swipe")
                        Text(model.gestureInputSummary)
                            .foregroundStyle(.secondary)
                    }
                    GridRow {
                        Text("Command")
                        Text(model.keyboardCommandSummary)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(model.swipeLastEvent)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Divider()

                ShortcutSettingsView(
                    settings: Binding(
                        get: { model.settings },
                        set: { model.updateSettings($0) }
                    )
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var diagnosticsSection: some View {
        GroupBox("Diagnostics") {
            if model.diagnostics.isEmpty {
                Text("No diagnostics")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(model.diagnostics.enumerated()), id: \.offset) { _, diagnostic in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(diagnostic.title)
                                .font(.headline)
                            Text(diagnostic.message)
                                .foregroundStyle(.secondary)
                            if let action = diagnostic.actionLabel {
                                Text(action)
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
        }
    }

    private var hudSection: some View {
        GroupBox("HUD") {
            if let hudState = model.hudState {
                HUDView(state: hudState)
            } else {
                Text("Run a switch action to preview HUD")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func displayTargetTitle(_ display: DisplayInfo) -> String {
        var labels = [display.name]
        if display.isPrimary {
            labels.append("primary")
        }
        if display.isBuiltin {
            labels.append("built-in")
        }
        return labels.joined(separator: " ")
    }
}
