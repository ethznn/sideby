import AppKit
import SwiftUI

/// Keeps the pinned column titles aligned with the horizontally scrolling cells.
/// Observe the native clip view: SwiftUI geometry preferences can remain unchanged
/// when AppKit scrolls an NSHostingView without another SwiftUI layout pass.
struct WorkspaceHorizontalScrollOffset: NSViewRepresentable {
    let changed: (CGFloat) -> Void
    func makeNSView(context: Context) -> ObserverView { ObserverView() }
    func updateNSView(_ view: ObserverView, context: Context) {
        view.changed = changed
        view.scheduleBinding()
    }
    static func dismantleNSView(_ view: ObserverView, coordinator: ()) { view.stop() }

    final class ObserverView: NSView {
        var changed: ((CGFloat) -> Void)?
        private weak var clip: NSClipView?
        private var observer: NSObjectProtocol?
        private var lastOffset: CGFloat?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); scheduleBinding() }
        override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); scheduleBinding() }
        func scheduleBinding() {
            DispatchQueue.main.async { [weak self] in self?.bind() }
        }
        private func bind() {
            guard window != nil, let content = enclosingScrollView?.contentView else { return }
            if clip !== content {
                stop(); clip = content
                content.postsBoundsChangedNotifications = true
                observer = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
                    object: content, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { self?.report() }
                    }
            }
            report()
        }
        private func report() {
            guard let clip else { return }
            let offset = -clip.bounds.minX
            guard lastOffset != offset else { return }
            lastOffset = offset
            DispatchQueue.main.async { [weak self] in self?.changed?(offset) }
        }
        func stop() {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil; clip = nil; lastOffset = nil
        }
        isolated deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}
