import AppKit
import SwiftUI

/// Keep click-to-select and drag-to-connect on the same card without relying on
/// a SwiftUI Button's competing click and drag recognizers.
struct WorkspaceDesktopDragSource<Content: View>: NSViewRepresentable {
    let enabled: Bool
    let label: String
    let identifier: String
    var isDraggable = true
    var accessibilityState: String? = nil
    var allowsMove = false
    let click: () -> Void
    let beginDrag: () -> String
    let endDrag: () -> Void
    @ViewBuilder let content: () -> Content

    func makeNSView(context: Context) -> CardButton {
        let view = CardButton()
        update(view)
        return view
    }

    func updateNSView(_ view: CardButton, context: Context) { update(view) }

    private func update(_ view: CardButton) {
        view.host.rootView = AnyView(content())
        view.isEnabled = enabled
        view.allowsMove = allowsMove
        view.isDraggable = isDraggable
        view.setAccessibilityLabel(label)
        view.setAccessibilityValue(accessibilityState)
        view.setAccessibilityIdentifier(identifier)
        view.click = click
        view.beginDrag = beginDrag
        view.endDrag = endDrag
        view.window?.invalidateCursorRects(for: view)
    }

    final class CardButton: NSButton, NSDraggingSource {
        let host = NSHostingView(rootView: AnyView(EmptyView()))
        var click: (() -> Void)?
        var beginDrag: (() -> String)?
        var endDrag: (() -> Void)?
        var allowsMove = false
        var isDraggable = true
        private var pressOrigin: NSPoint?

        override init(frame: NSRect) {
            super.init(frame: frame)
            title = ""
            isBordered = false
            setButtonType(.momentaryPushIn)
            target = self
            action = #selector(chooseCard)
            setAccessibilityElement(true)
            host.setAccessibilityElement(false)
            host.autoresizingMask = [.width, .height]
            addSubview(host)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

        override func layout() { super.layout(); host.frame = bounds }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }
        override func hitTest(_ point: NSPoint) -> NSView? {
            bounds.contains(convert(point, from: superview)) ? self : nil
        }
        override func resetCursorRects() {
            super.resetCursorRects()
            addCursorRect(bounds, cursor: !isEnabled ? .arrow : isDraggable ? .openHand : .pointingHand)
        }
        @objc private func chooseCard() { if isEnabled { click?() } }

        override func mouseDown(with event: NSEvent) {
            pressOrigin = isEnabled ? event.locationInWindow : nil
        }

        override func mouseUp(with event: NSEvent) {
            defer { pressOrigin = nil }
            guard pressOrigin != nil, isEnabled,
                  bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
            performClick(nil)
        }

        override func mouseDragged(with event: NSEvent) {
            guard isEnabled, isDraggable, let origin = pressOrigin else { return }
            let point = event.locationInWindow
            guard hypot(point.x - origin.x, point.y - origin.y) >= 4 else { return }
            pressOrigin = nil
            guard let payload = beginDrag?(), !payload.isEmpty else { return }
            let item = NSPasteboardItem()
            item.setString(payload, forType: .string)
            let draggingItem = NSDraggingItem(pasteboardWriter: item)
            layoutSubtreeIfNeeded()
            let preview = NSImage(size: bounds.size)
            if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: bitmap)
                preview.addRepresentation(bitmap)
            }
            draggingItem.setDraggingFrame(bounds, contents: preview)
            NSCursor.closedHand.set()
            let session = beginDraggingSession(with: [draggingItem], event: event, source: self)
            session.animatesToStartingPositionsOnCancelOrFail = true
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            allowsMove && context == .withinApplication ? [.copy, .move] : .copy
        }
        func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { false }
        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            endDrag?()
            NSCursor.openHand.set()
        }
    }
}
