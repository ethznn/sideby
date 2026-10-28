import AppKit
import Foundation

// Public-API-only observer. A Space-change notification carries no Space ID;
// display IDs below identify physical displays, never desktop Spaces.
@MainActor
final class SpaceStateObserver: NSObject, NSApplicationDelegate {
    let duration: TimeInterval
    let started = ProcessInfo.processInfo.systemUptime
    var changes = 0
    var observer: NSObjectProtocol?
    var timer: Timer?

    init(duration: TimeInterval) { self.duration = duration }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = NSWorkspace.shared.notificationCenter
        observer = center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.changes += 1
                    self?.sample(event: "space-change")
                }
            }
        sample(event: "ready")
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if ProcessInfo.processInfo.systemUptime - self.started >= self.duration {
                    self.sample(event: "duration-complete")
                    NSApp.terminate(nil)
                } else { self.sample(event: "sample") }
            }
        }
    }

    func sample(event: String) {
            let pointer = NSEvent.mouseLocation
            let pointerScreen = NSScreen.screens.first(where: { $0.frame.contains(pointer) })
            let displays = NSScreen.screens.enumerated().map { index, screen -> [String: Any] in
                ["display": index + 1,
                 "physicalDisplayID": (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0]
            }
            let row: [String: Any] = ["uptime": ProcessInfo.processInfo.systemUptime,
                "event": event, "observerLifecycle": "NSApplication-prohibited",
                "wallTime": ISO8601DateFormatter().string(from: Date()), "apiScope": "public-only",
                "spaceIDAvailable": false, "spaceChangeNotifications": changes,
                "systemPresentationOptions": NSApp.currentSystemPresentationOptions.rawValue,
                "frontmostAppFullScreen": NSApp.currentSystemPresentationOptions.contains(.fullScreen),
                "pointerLocation": [pointer.x, pointer.y],
                "pointerDisplay": (pointerScreen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0,
                "frontmostPID": NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1,
                "displays": displays]
            if let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) {
                try? FileHandle.standardOutput.write(contentsOf: data + Data([10]))
            }
    }
}

@main
@MainActor
struct ObserveSpaceState {
    static func main() {
        guard CommandLine.arguments.count == 2, let duration = Double(CommandLine.arguments[1]),
              duration > 0, duration <= 900 else { return }
        let delegate = SpaceStateObserver(duration: duration)
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
