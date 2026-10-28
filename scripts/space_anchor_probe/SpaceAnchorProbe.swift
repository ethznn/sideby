import AppKit
import CoreGraphics
import Foundation

@MainActor
final class AnchorWindow: NSWindow {
    let record: AnchorRecord
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init(record: AnchorRecord, frame: NSRect) {
        self.record = record
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        setFrame(frame, display: false)
        identifier = NSUserInterfaceItemIdentifier("anchor." + record.id)
        title = "Anchor " + record.displayLabel
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        canHide = false
        isExcludedFromWindowsMenu = true
        collectionBehavior = [.managed, .ignoresCycle]
        isRestorable = true
        restorationClass = AnchorRestoration.self
    }

    override func encodeRestorableState(with coder: NSCoder) {
        super.encodeRestorableState(with: coder)
        coder.encode(record.id as NSString, forKey: "probeAnchorID")
        ProbeController.shared?.emit("anchor-encoded", ["display": record.displayLabel])
    }
}

@MainActor
final class AnchorRestoration: NSObject, NSWindowRestoration {
    static func restoreWindow(withIdentifier identifier: NSUserInterfaceItemIdentifier,
                              state: NSCoder, completionHandler: @escaping (NSWindow?, Error?) -> Void) {
        guard let controller = ProbeController.shared,
              let id = state.decodeObject(of: NSString.self, forKey: "probeAnchorID") as String?,
              identifier.rawValue == "anchor." + id,
              let record = controller.state.anchors.first(where: { $0.id == id }) else {
            completionHandler(nil, ProbeFailure("unknown-restoration-record"))
            return
        }
        // AppKit, not our saved coordinates, must restore the Space assignment.
        let window = AnchorWindow(record: record, frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        controller.windows[id] = window
        controller.restoredIDs.insert(id)
        controller.emit("restoration-callback", ["display": record.displayLabel])
        completionHandler(window, nil)
    }
}

@MainActor
final class ProbeController: NSObject, NSApplicationDelegate {
    static var shared: ProbeController?
    var state = ProbeState()
    var windows: [String: AnchorWindow] = [:]
    var restoredIDs: Set<String> = []
    var observer: NSObjectProtocol?
    var statusItem: NSStatusItem?
    var panel: NSPanel?
    var summary: NSTextField?
    var busy = false
    var changeCount = 0
    var status = "Capture A, visit another desktop, then capture B."
    var started = Date()
    var inputTask: Task<Void, Never>?
    var output: FileHandle?

    var storageURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SpaceAnchorProbe", isDirectory: true)
    }
    var stateURL: URL { storageURL.appendingPathComponent("state.json") }

    override init() {
        super.init()
        Self.shared = self
        do {
            try FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: stateURL.path) {
                state = try JSONDecoder().decode(ProbeState.self, from: Data(contentsOf: stateURL))
            }
            let log = storageURL.appendingPathComponent("events.jsonl")
            if !FileManager.default.fileExists(atPath: log.path) { FileManager.default.createFile(atPath: log.path, contents: nil) }
            output = try FileHandle(forWritingTo: log)
            try output?.seekToEnd()
        } catch { status = "Storage error: \(error.localizedDescription)" }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        emit("will-launch", ["savedWorkspaces": state.workspaces.count, "savedAnchors": state.anchors.count])
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.changeCount += 1
                self.emit("space-change", self.snapshot())
                self.refreshUI()
            }
        }
        installUI()
        emit("ready", snapshot())
        // Stdin is an optional test harness; the app itself posts no keyboard events.
        inputTask = Task { @MainActor in
            do {
                for try await line in FileHandle.standardInput.bytes.lines { command(line) }
            } catch { emit("stdin-closed") }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.report() }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
    func applicationShouldSaveSecureApplicationState(_ app: NSApplication) -> Bool { true }
    func applicationShouldRestoreSecureApplicationState(_ app: NSApplication) -> Bool { true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !busy else { return .terminateCancel }
        do { try persist() } catch { emit("save-error", ["reason": String(describing: error)]) }
        // Keep anchors open so AppKit can encode and restore their placements.
        emit("quitting", snapshot())
        return .terminateNow
    }

    func emit(_ event: String, _ fields: [String: Any] = [:]) {
        var row = fields
        row["event"] = event
        row["elapsed"] = round(Date().timeIntervalSince(started) * 1000) / 1000
        guard let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) else { return }
        let line = data + Data([10])
        try? output?.write(contentsOf: line)
        try? FileHandle.standardOutput.write(contentsOf: line)
    }

    func displayID(_ screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    func connectedScreens() -> [(NSScreen, String)] {
        NSScreen.screens.compactMap { screen in displayID(screen).map { (screen, $0) } }
    }

    var activeIDs: Set<String> { Set(windows.compactMap { $0.value.isOnActiveSpace ? $0.key : nil }) }

    func snapshot() -> [String: Any] {
        let active = activeIDs
        return [
            "sandboxContainer": NSHomeDirectory().contains("/Library/Containers/"),
            "screens": NSScreen.screens.count,
            "spaceChangeCount": changeCount,
            "restoredCount": restoredIDs.count,
            "busy": busy,
            "anchors": state.anchors.enumerated().map { index, record -> [String: Any] in
                let window = windows[record.id]
                return ["anchor": index + 1, "display": record.displayLabel,
                        "live": window != nil, "active": active.contains(record.id),
                        "onExpectedDisplay": window?.screen.flatMap(displayID) == record.displayID,
                        "restored": restoredIDs.contains(record.id)]
            },
            "workspaces": state.workspaces.map { workspace -> [String: Any] in
                ["name": workspace.name,
                 "anchors": workspace.anchorIDs.map { id in (state.anchors.firstIndex { $0.id == id } ?? -1) + 1 },
                 "active": workspace.anchorIDs.allSatisfy { active.contains($0) }]
            }
        ]
    }

    func persist() throws {
        try JSONEncoder().encode(state).write(to: stateURL, options: .atomic)
        NSApp.invalidateRestorableState()
        for window in windows.values { window.invalidateRestorableState() }
    }

    func capture(_ name: String) async {
        guard !busy else { return }
        busy = true
        defer { busy = false; refreshUI() }
        let oldState = state
        var made: [String] = []
        do {
            guard state.anchors.allSatisfy({ windows[$0.id] != nil }) else { throw ProbeFailure("unrestored-anchors-reset-required") }
            let screens = connectedScreens()
            guard !screens.isEmpty else { throw ProbeFailure("no-displays") }
            var records: [AnchorRecord] = []
            for (index, pair) in screens.enumerated() {
                let (screen, id) = pair
                let existing = state.anchors.filter { $0.displayID == id && activeIDs.contains($0.id) }
                guard existing.count <= 1 else { throw ProbeFailure("ambiguous-anchors-on-same-space") }
                if let record = existing.first { records.append(record); continue }
                let label = state.anchors.first(where: { $0.displayID == id })?.displayLabel ?? "Display \(index + 1)"
                let record = AnchorRecord(id: UUID().uuidString, displayID: id, displayLabel: label)
                let frame = NSRect(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY, width: 1, height: 1)
                let window = AnchorWindow(record: record, frame: frame)
                window.collectionBehavior.insert(.moveToActiveSpace)
                window.orderBack(nil)
                window.collectionBehavior.remove(.moveToActiveSpace)
                windows[record.id] = window
                made.append(record.id)
                records.append(record)
            }
            try await Task.sleep(for: .milliseconds(250))
            for record in records {
                guard let window = windows[record.id], window.isOnActiveSpace,
                      window.screen.flatMap(displayID) == record.displayID else { throw ProbeFailure("anchor-placement-failed") }
            }
            state.saveWorkspace(name, anchors: records)
            try persist()
            status = "Captured \(name) on \(records.count) displays."
            emit("captured", ["name": name, "snapshot": snapshot()])
        } catch {
            state = oldState
            for id in made { windows.removeValue(forKey: id)?.close() }
            status = "Capture failed: \(error)"
            emit("capture-failed", ["name": name, "reason": String(describing: error)])
        }
    }

    func switchTo(_ name: String) async {
        guard !busy else { return }
        busy = true
        defer { busy = false; refreshUI() }
        let before = changeCount
        let begin = Date()
        do {
            let targets = try state.targets(for: name)
            try validate(targets)
            emit("switch-start", ["name": name, "snapshot": snapshot()])
            for target in targets {
                guard let window = windows[target.id] else { throw ProbeFailure("anchor-not-restored") }
                if window.isOnActiveSpace { continue }
                let oldActive = Set(state.anchors.filter { $0.displayID == target.displayID && activeIDs.contains($0.id) }.map(\.id))
                NSApp.activate()
                window.makeKeyAndOrderFront(nil)
                let deadline = Date().addingTimeInterval(3)
                while Date() < deadline {
                    try await Task.sleep(for: .milliseconds(100))
                    if window.isOnActiveSpace && oldActive.isDisjoint(with: activeIDs) { break }
                }
                guard window.isOnActiveSpace else { throw ProbeFailure("target-did-not-become-active") }
                guard oldActive.isDisjoint(with: activeIDs) else { throw ProbeFailure("source-still-active-anchor-may-have-moved") }
                try validate(targets)
            }
            try await Task.sleep(for: .milliseconds(250))
            try validate(targets)
            guard targets.allSatisfy({ activeIDs.contains($0.id) }) else { throw ProbeFailure("earlier-display-reverted") }
            status = "Verified \(name). \(changeCount - before) Space notifications."
            emit("switch-verified", ["name": name, "duration": Date().timeIntervalSince(begin),
                                     "notifications": changeCount - before, "snapshot": snapshot()])
        } catch {
            status = "Switch failed: \(error)"
            emit("switch-failed", ["name": name, "reason": String(describing: error), "snapshot": snapshot()])
        }
    }

    func validate(_ targets: [AnchorRecord]) throws {
        try state.validateSelection(targets, liveIDs: Set(windows.keys),
                                    connectedDisplayIDs: Set(connectedScreens().map(\.1)), activeIDs: activeIDs)
        for target in targets {
            guard windows[target.id]?.screen.flatMap(displayID) == target.displayID else { throw ProbeFailure("anchor-moved-to-another-display") }
        }
    }

    func command(_ line: String) {
        let parts = line.split(separator: " ").map(String.init)
        guard let first = parts.first else { return }
        switch first {
        case "capture" where parts.count == 2: Task { await capture(parts[1]) }
        case "goto" where parts.count == 2: Task { await switchTo(parts[1]) }
        case "status": report()
        case "show": panel?.orderFrontRegardless()
        case "quit": NSApp.terminate(nil)
        case "reset": reset()
        default: emit("unknown-command")
        }
    }

    @objc func action(_ sender: NSButton) { command(sender.identifier?.rawValue ?? "") }
    @objc func menuAction(_ sender: NSMenuItem) { command(sender.representedObject as? String ?? "") }

    func report() { emit("status", snapshot()); refreshUI() }

    func reset() {
        guard !busy else { return }
        // Only the independent probe's own synthetic test data is reset.
        for window in windows.values { window.close() }
        windows.removeAll(); restoredIDs.removeAll(); state = ProbeState()
        do { try persist(); status = "Probe data reset." }
        catch { status = "Reset save failed: \(error)" }
        emit("reset"); refreshUI()
    }

    func installUI() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "Anchor Lab"
        let menu = NSMenu()
        for (title, command) in [("Show controls", "show"), ("Capture A", "capture A"),
                                 ("Capture B", "capture B"), ("Switch to A", "goto A"),
                                 ("Switch to B", "goto B"), ("Save and quit", "quit")] {
            let entry = NSMenuItem(title: title, action: #selector(menuAction(_:)), keyEquivalent: "")
            entry.target = self; entry.representedObject = command; menu.addItem(entry)
        }
        item.menu = menu; statusItem = item
        let panel = NSPanel(contentRect: NSRect(x: 100, y: 100, width: 500, height: 310),
                            styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Space Anchor Probe"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isRestorable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.level = .floating
        let text = NSTextField(wrappingLabelWithString: "")
        text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        text.frame = NSRect(x: 20, y: 100, width: 460, height: 190)
        panel.contentView?.addSubview(text); summary = text
        let actions = [("Capture A", "capture A"), ("Capture B", "capture B"), ("Go to A", "goto A"),
                       ("Go to B", "goto B"), ("Snapshot", "status"), ("Save & Quit", "quit")]
        for (index, entry) in actions.enumerated() {
            let button = NSButton(title: entry.0, target: self, action: #selector(action(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(entry.1)
            button.bezelStyle = .rounded
            button.frame = NSRect(x: 18 + (index % 3) * 158, y: 58 - (index / 3) * 36, width: 148, height: 30)
            panel.contentView?.addSubview(button)
        }
        self.panel = panel
        refreshUI()
        panel.orderFrontRegardless()
    }

    func refreshUI() {
        var lines = ["PUBLIC API · APP SANDBOX", "Displays: \(NSScreen.screens.count)  Restored: \(restoredIDs.count)"]
        for workspace in state.workspaces {
            let flags = workspace.anchorIDs.map { id -> String in
                guard let record = state.anchors.first(where: { $0.id == id }) else { return "invalid" }
                return record.displayLabel + ": " + (windows[id] == nil ? "unresolved" : activeIDs.contains(id) ? "HERE" : "away")
            }
            lines.append(workspace.name + "  " + flags.joined(separator: " | "))
        }
        lines += ["", busy ? "Working…" : status]
        summary?.stringValue = lines.joined(separator: "\n")
    }
}

@main
@MainActor
struct Main {
    static func main() {
        // Disabled after a manual multi-display trial caused input/focus failure.
        // Do not initialize NSApplication or restore any anchor windows here.
        // Retain the implementation above for static investigation only.
        let message = "SpaceAnchorProbe is disabled after an input/focus failure. Do not run interactive trials on the working desktop.\n"
        FileHandle.standardError.write(Data(message.utf8))
    }
}
