import AppKit
import Foundation

@MainActor
final class TrialController: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTextFieldDelegate {
    var windows: [String: NSWindow] = [:]
    var fields: [String: NSTextField] = [:]
    var clicks: [String: Int] = [:]
    var observers: [NSObjectProtocol] = []
    var timer: Timer?
    var lastRequest = ""
    var switchUsed = false
    var pending: (name: String, deadline: TimeInterval, stableSince: TimeInterval?)?
    var preparation: (deadline: TimeInterval, awaySince: TimeInterval?)?
    var placement: (deadline: TimeInterval, stableSince: TimeInterval?)?
    var sourceReady = false
    var targetDisplay: UInt32?
    let started = ProcessInfo.processInfo.systemUptime
    let directory: URL
    let output: FileHandle
    let placementDelayMilliseconds: Int

    init(token: String, placementDelayMilliseconds: Int) throws {
        self.placementDelayMilliseconds = placementDelayMilliseconds
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SpaceTransitionTrial/" + token, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let log = directory.appendingPathComponent("events.jsonl")
        guard FileManager.default.createFile(atPath: log.path, contents: nil) else {
            throw NSError(domain: "Trial", code: 1)
        }
        output = try FileHandle(forWritingTo: log)
        super.init()
    }

    func emit(_ event: String, _ extra: [String: Any] = [:]) {
        var row = extra
        row["event"] = event
        row["uptime"] = ProcessInfo.processInfo.systemUptime
        row["wallTime"] = ISO8601DateFormatter().string(from: Date())
        row["elapsed"] = ProcessInfo.processInfo.systemUptime - started
        row["appActive"] = NSApp.isActive
        row["systemPresentationOptions"] = NSApp.currentSystemPresentationOptions.rawValue
        row["frontmostAppFullScreen"] = NSApp.currentSystemPresentationOptions.contains(.fullScreen)
        let pointer = NSEvent.mouseLocation
        row["pointerLocation"] = [pointer.x, pointer.y]
        row["pointerDisplay"] = displayID(NSScreen.screens.first(where: { $0.frame.contains(pointer) })) ?? 0
        row["mainScreenDisplay"] = displayID(NSScreen.main) ?? 0
        row["frontmostIsTrial"] = NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid()
        row["windows"] = windows.keys.sorted().map { name -> [String: Any] in
            let w = windows[name]!
            return ["name": name, "number": w.windowNumber, "activeSpace": w.isOnActiveSpace,
                    "key": w.isKeyWindow, "main": w.isMainWindow,
                    "visible": w.isVisible, "inputLength": fields[name]?.stringValue.count ?? 0,
                    "clickCount": clicks[name] ?? 0,
                    "frame": [w.frame.origin.x, w.frame.origin.y, w.frame.width, w.frame.height],
                    "collectionBehavior": w.collectionBehavior.rawValue,
                    "occlusionVisible": w.occlusionState.contains(.visible),
                    "display": (w.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) else { return }
        try? output.write(contentsOf: data + Data([10]))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let appMenu = NSMenu()
        let root = NSMenuItem()
        let submenu = NSMenu()
        submenu.addItem(withTitle: "Quit Space Transition Trial", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        root.submenu = submenu
        appMenu.addItem(root)
        NSApp.mainMenu = appMenu
        for notification in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
                             NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                             NSWindow.didChangeScreenNotification, NSWindow.didMoveNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: notification, object: nil, queue: .main) { [weak self] note in
                let name = note.name.rawValue
                MainActor.assumeIsolated { self?.emit("appkit-event", ["notification": name]) }
            })
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.emit("space-change") }
            })
        makeWindow("A")
        emit("ready", ["stage": "visible-window-one-target-display", "pid": getpid(),
                       "targetDisplay": targetDisplay ?? 0,
                       "placementDelayMilliseconds": placementDelayMilliseconds])
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        tick()
    }

    func makeWindow(_ name: String) {
        guard windows[name] == nil else { return }
        if targetDisplay == nil { targetDisplay = displayID(NSScreen.screens.first) }
        guard let targetDisplay, let screen = NSScreen.screens.first(where: { displayID($0) == targetDisplay }) else {
            emit("preparation-failed", ["reason": "target-display-unavailable"])
            NSApp.terminate(nil)
            return
        }
        // The screen initializer takes coordinates relative to that screen's
        // origin, unlike NSScreen.visibleFrame, which uses desktop coordinates.
        let frame = NSRect(x: screen.visibleFrame.midX - screen.frame.minX - 240,
                           y: screen.visibleFrame.midY - screen.frame.minY - 130,
                           width: 480, height: 260)
        let window = NSWindow(contentRect: frame, styleMask: [.titled, .closable],
                              backing: .buffered, defer: false, screen: screen)
        window.title = "Space Transition Trial — " + name
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.collectionBehavior = [.managed, .ignoresCycle, .moveToActiveSpace]
        window.delegate = self
        let label = NSTextField(labelWithString: "Stage 1 · Visible window " + name + "\nType the test token below, then click the button.")
        label.frame = NSRect(x: 24, y: 165, width: 432, height: 65)
        window.contentView?.addSubview(label)
        let field = NSTextField(frame: NSRect(x: 24, y: 110, width: 432, height: 32))
        field.placeholderString = "Input verification " + name
        field.identifier = NSUserInterfaceItemIdentifier(name)
        field.delegate = self
        window.contentView?.addSubview(field)
        let button = NSButton(title: "Verify click " + name, target: self, action: #selector(clicked(_:)))
        button.identifier = NSUserInterfaceItemIdentifier(name)
        button.frame = NSRect(x: 24, y: 52, width: 190, height: 36)
        button.bezelStyle = .rounded
        window.contentView?.addSubview(button)
        let stop = NSButton(title: "Stop trial", target: NSApp, action: #selector(NSApplication.terminate(_:)))
        stop.frame = NSRect(x: 270, y: 52, width: 180, height: 36)
        stop.bezelStyle = .rounded
        window.contentView?.addSubview(stop)
        if name == "B" {
            let back = NSButton(title: "Return to A once", target: self, action: #selector(returnToA(_:)))
            back.frame = NSRect(x: 24, y: 10, width: 190, height: 32)
            back.bezelStyle = .rounded
            window.contentView?.addSubview(back)
        }
        fields[name] = field
        windows[name] = window
        window.orderFront(nil)
        // Request placement on the current desktop. The later preparation gate
        // must verify actual display/membership after this option is removed.
        if placementDelayMilliseconds == 0 {
            window.collectionBehavior.remove(.moveToActiveSpace)
            emit("placement-option-cleared", ["name": name])
        } else {
            Timer.scheduledTimer(withTimeInterval: Double(placementDelayMilliseconds) / 1000,
                                 repeats: false) { [weak self, weak window] _ in
                MainActor.assumeIsolated {
                    guard let self, let window else { return }
                    self.emit("placement-option-clearing", ["name": name])
                    window.collectionBehavior.remove(.moveToActiveSpace)
                    self.emit("placement-option-cleared", ["name": name])
                }
            }
        }
        emit("created", ["name": name])
        if name == "B" { placement = (ProcessInfo.processInfo.systemUptime + 5, nil) }
    }

    func displayID(_ screen: NSScreen?) -> UInt32? {
        (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    var sourcePlacementMatches: Bool {
        guard let a = windows["A"], let b = windows["B"], let targetDisplay else { return false }
        return !a.isOnActiveSpace && b.isOnActiveSpace &&
            displayID(a.screen) == targetDisplay && displayID(b.screen) == targetDisplay &&
            !a.collectionBehavior.contains(.moveToActiveSpace) && !b.collectionBehavior.contains(.moveToActiveSpace)
    }

    @objc func returnToA(_ sender: NSButton) { jumpToA(trigger: "visible-button") }

    func jumpToA(trigger: String) {
        guard !switchUsed, pending == nil, sourceReady, sourcePlacementMatches,
              let target = windows["A"] else {
            emit("request-rejected", ["reason": "requires-stable-same-display-source-and-unused-switch", "trigger": trigger])
            return
        }
        switchUsed = true
        pending = ("A", ProcessInfo.processInfo.systemUptime + 5, nil)
        emit("switch-requested", ["name": "A", "trigger": trigger])
        NSApp.activate()
        target.makeKeyAndOrderFront(nil)
        target.makeFirstResponder(fields["A"])
    }

    @objc func clicked(_ sender: NSButton) {
        let name = sender.identifier!.rawValue
        clicks[name, default: 0] += 1
        sender.title = "Click received " + name + " (\(clicks[name]!))"
        emit("click-received", ["name": name])
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        emit("text-changed", ["name": field.identifier?.rawValue ?? "unknown"])
    }

    func tick() {
        try? Data(String(ProcessInfo.processInfo.systemUptime).utf8)
            .write(to: directory.appendingPathComponent("heartbeat"), options: .atomic)
        if let data = try? Data(contentsOf: directory.appendingPathComponent("request.json")),
           let request = try? JSONSerialization.jsonObject(with: data) as? [String: String],
           let id = request["id"], id != lastRequest, let command = request["command"] {
            lastRequest = id
            emit("request", ["id": id, "command": command])
            switch command {
            case "create-B":
                guard windows["A"]?.isOnActiveSpace == false, windows["B"] == nil else {
                    emit("request-rejected", ["reason": "requires-A-away-and-no-B"])
                    break
                }
                makeWindow("B")
            case "prepare-B-when-away":
                guard windows["A"]?.isOnActiveSpace == true,
                      displayID(windows["A"]?.screen) == targetDisplay,
                      windows["B"] == nil, preparation == nil, !switchUsed else {
                    emit("request-rejected", ["reason": "requires-A-here-and-unused-preparation"])
                    break
                }
                preparation = (ProcessInfo.processInfo.systemUptime + 120, nil)
                emit("preparation-armed")
            case "snapshot": emit("snapshot")
            case "quit": NSApp.terminate(nil)
            case "jump-A-once": jumpToA(trigger: "file-request")
            default: emit("request-rejected", ["reason": "unknown-command"])
            }
        }
        if var placement {
            let now = ProcessInfo.processInfo.systemUptime
            if now > placement.deadline {
                emit("preparation-failed", ["reason": "A-away-B-here-on-target-display-not-stable"])
                self.placement = nil
                NSApp.terminate(nil)
            } else if sourcePlacementMatches {
                if placement.stableSince == nil { placement.stableSince = now }
                if now - placement.stableSince! >= 2 {
                    sourceReady = true
                    self.placement = nil
                    emit("source-ready")
                } else { self.placement = placement }
            } else {
                placement.stableSince = nil
                self.placement = placement
            }
        }
        if sourceReady && !switchUsed && !sourcePlacementMatches {
            emit("preparation-failed", ["reason": "source-placement-changed-after-readiness"])
            NSApp.terminate(nil)
        }
        if var preparation {
            let now = ProcessInfo.processInfo.systemUptime
            if now > preparation.deadline {
                emit("preparation-timeout")
                self.preparation = nil
                NSApp.terminate(nil)
            } else if windows["A"]?.isOnActiveSpace == false {
                if preparation.awaySince == nil { preparation.awaySince = now }
                if now - preparation.awaySince! >= 2 {
                    self.preparation = nil
                    makeWindow("B")
                    emit("created-B-after-A-away")
                } else { self.preparation = preparation }
            } else {
                preparation.awaySince = nil
                self.preparation = preparation
            }
        }
        guard var trial = pending, let target = windows[trial.name] else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if now > trial.deadline {
            emit("transition-timeout")
            pending = nil
            NSApp.terminate(nil)
        } else if NSApp.isActive && target.isOnActiveSpace && target.isKeyWindow &&
                    windows["B"]?.isOnActiveSpace == false &&
                    displayID(target.screen) == targetDisplay && displayID(windows["B"]?.screen) == targetDisplay {
            if trial.stableSince == nil { trial.stableSince = now }
            if now - trial.stableSince! >= 1 {
                emit("membership-and-key-observed", ["inputVerified": false, "renderingVerified": false])
                pending = nil
            } else { pending = trial }
        } else {
            trial.stableSince = nil
            pending = trial
        }
    }

    func windowWillClose(_ notification: Notification) { NSApp.terminate(nil) }
    func applicationShouldSaveSecureApplicationState(_ app: NSApplication) -> Bool { false }
    func applicationShouldRestoreSecureApplicationState(_ app: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { emit("terminated"); try? output.synchronize() }
}

@main
@MainActor
struct VisibleTransitionTrial {
    static func main() throws {
        guard (2...3).contains(CommandLine.arguments.count), UUID(uuidString: CommandLine.arguments[1]) != nil else {
            print("Launch only through supervise_trial.py; a unique trial token is required.")
            return
        }
        let display: UInt32?
        if CommandLine.arguments.count == 3 {
            guard let requested = UInt32(CommandLine.arguments[2]), requested != 0 else { return }
            display = requested
        } else { display = nil }
        guard let delay = Int(ProcessInfo.processInfo.environment["SPACE_TRIAL_PLACEMENT_DELAY_MS"] ?? "0"),
              [0, 500].contains(delay) else { return }
        let controller = try TrialController(token: CommandLine.arguments[1], placementDelayMilliseconds: delay)
        controller.targetDisplay = display
        let app = NSApplication.shared
        app.delegate = controller
        app.run()
        withExtendedLifetime(controller) {}
    }
}
