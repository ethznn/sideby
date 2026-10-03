import AppKit
import SwiftUI

/// SwiftUI's onDrag has no completion callback. Clear transient highlights even
/// when a native drag is cancelled or released outside a valid drop target.
struct WorkspaceDragCompletion: NSViewRepresentable {
    let dragID: UUID?
    let finished: () -> Void
    func makeNSView(context: Context) -> Monitor { Monitor() }
    func updateNSView(_ view: Monitor, context: Context) { view.finished = finished; view.track(dragID) }
    static func dismantleNSView(_ view: Monitor, coordinator: ()) { view.track(nil) }

    final class Monitor: NSView {
        var finished: (() -> Void)?
        private var local: Any?
        private var global: Any?
        private var dragID: UUID?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        func track(_ id: UUID?) {
            dragID = id
            if id == nil {
                if let local { NSEvent.removeMonitor(local); self.local = nil }
                if let global { NSEvent.removeMonitor(global); self.global = nil }
                return
            }
            guard local == nil else { return }
            local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp, .keyDown]) { [weak self] event in
                if event.type == .leftMouseUp || event.keyCode == 53 {
                    MainActor.assumeIsolated { self?.finishAfterDropDispatch() }
                }
                return event
            }
            global = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
                MainActor.assumeIsolated { self?.finishAfterDropDispatch() }
            }
        }
        private func finishAfterDropDispatch() {
            let expected = dragID
            // Allow SwiftUI's drop dispatch to consume the active payload before
            // clearing highlights; the ID guard protects a subsequent drag.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self, self.dragID == expected else { return }
                self.finished?()
            }
        }
        isolated deinit {
            if let local { NSEvent.removeMonitor(local) }
            if let global { NSEvent.removeMonitor(global) }
        }
    }
}
