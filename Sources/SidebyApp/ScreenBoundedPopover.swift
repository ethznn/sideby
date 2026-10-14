import AppKit
import SwiftUI

extension View {
    /// Keep the popover on the display containing the clicked control, including
    /// after AppKit or a late content measurement changes its frame.
    func screenBoundedPopover<Popup: View>(isPresented: Binding<Bool>, width: CGFloat,
                                          @ViewBuilder content: () -> Popup) -> some View {
        modifier(ScreenBoundedPopover(isPresented: isPresented, width: width, popup: content()))
    }
}

private struct ScreenBoundedPopover<Popup: View>: ViewModifier {
    @Binding var isPresented: Bool
    let width: CGFloat
    let popup: Popup
    @State private var anchor = PopoverAnchor()

    func body(content: Content) -> some View {
        content.background(PopoverAnchorReader(anchor: anchor))
            .popover(isPresented: $isPresented) {
                BoundedPopoverContent(width: width, anchor: anchor, popup: popup)
            }
    }
}

private struct BoundedPopoverContent<Popup: View>: View {
    let width: CGFloat
    let anchor: PopoverAnchor
    let popup: Popup
    @State private var contentHeight: CGFloat = 400
    @State private var available = NSSize(width: 600, height: 600)

    var body: some View {
        // Usually only the Space list scrolls. On a very short display the
        // entire picker can scroll too, so its explanation and disconnect
        // action remain reachable rather than being clipped by the window.
        ScrollView(.vertical) {
            popup.frame(maxWidth: .infinity).fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { geometry in
                    Color.clear.onChange(of: geometry.size.height, initial: true) { _, height in
                        if height > 0 { contentHeight = ceil(height) }
                    }
                })
        }
        .frame(width: min(width, available.width), height: min(contentHeight, available.height))
        .background(PopoverWindowConstraint(anchor: anchor) { size in
            if available != size { available = size }
        })
    }
}

@MainActor private final class PopoverAnchor {
    weak var view: NSView?

    var screen: NSScreen? {
        guard let view, let window = view.window else { return nil }
        let rect = window.convertToScreen(view.convert(view.bounds, to: nil))
        return NSScreen.screens.first { $0.frame.contains(NSPoint(x: rect.midX, y: rect.midY)) }
            ?? window.screen
    }
}

private struct PopoverAnchorReader: NSViewRepresentable {
    let anchor: PopoverAnchor
    func makeNSView(context: Context) -> NSView {
        let view = AnchorView()
        anchor.view = view
        return view
    }
    func updateNSView(_ view: NSView, context: Context) { anchor.view = view }
    final class AnchorView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

enum PopoverScreenLayout {
    static func bounds(in visibleFrame: NSRect) -> NSRect {
        visibleFrame.insetBy(dx: min(8, visibleFrame.width / 4), dy: min(8, visibleFrame.height / 4))
    }

    static func origin(for frame: NSRect, in bounds: NSRect) -> NSPoint {
        NSPoint(x: max(bounds.minX, min(frame.minX, bounds.maxX - frame.width)),
                y: max(bounds.minY, min(frame.minY, bounds.maxY - frame.height)))
    }

    static func contentSize(window: NSSize, content: NSSize, bounds: NSSize) -> NSSize {
        NSSize(width: max(1, bounds.width - max(0, window.width - content.width)),
               height: max(1, bounds.height - max(0, window.height - content.height)))
    }
}

private struct PopoverWindowConstraint: NSViewRepresentable {
    let anchor: PopoverAnchor
    let availableChanged: (NSSize) -> Void

    func makeNSView(context: Context) -> ConstraintView { ConstraintView() }
    func updateNSView(_ view: ConstraintView, context: Context) {
        view.anchor = anchor
        view.availableChanged = availableChanged
        view.scheduleConstraint()
    }

    final class ConstraintView: NSView {
        var anchor: PopoverAnchor?
        var availableChanged: ((NSSize) -> Void)?
        private var observations: [NSObjectProtocol] = []
        private var pending = false

        isolated deinit {
            observations.forEach(NotificationCenter.default.removeObserver)
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observations.forEach(NotificationCenter.default.removeObserver)
            observations.removeAll()
            guard let window else { return }
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.didChangeScreenNotification] {
                observations.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.scheduleConstraint() }
                })
            }
            observations.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.scheduleConstraint() }
                })
            scheduleConstraint()
        }

        override func layout() {
            super.layout()
            scheduleConstraint()
        }

        func scheduleConstraint() {
            guard !pending else { return }
            pending = true
            // Let SwiftUI/AppKit finish sizing and anchoring before correcting
            // the window; changing it inside a layout pass causes feedback loops.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.pending = false
                guard let window = self.window, window !== self.anchor?.view?.window,
                      self.bounds.width > 0, self.bounds.height > 0,
                      let screen = self.anchor?.screen ?? window.screen else { return }
                let bounds = PopoverScreenLayout.bounds(in: screen.visibleFrame)
                self.availableChanged?(PopoverScreenLayout.contentSize(window: window.frame.size,
                    content: self.bounds.size, bounds: bounds.size))
                let origin = PopoverScreenLayout.origin(for: window.frame, in: bounds)
                if abs(origin.x - window.frame.minX) > 0.5 || abs(origin.y - window.frame.minY) > 0.5 {
                    window.setFrameOrigin(origin)
                }
            }
        }
    }
}
