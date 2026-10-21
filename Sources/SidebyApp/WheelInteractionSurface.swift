import AppKit
import SwiftUI

/// One native surface owns pointer gestures across the curved sectors. SwiftUI
/// buttons underneath retain keyboard/VoiceOver actions; the center and tools
/// pass through. A native drag prevents mouse-up from also switching Spaces.
struct WheelInteractionSurface: NSViewRepresentable {
    let count: Int
    let geometry: HeldWorkspaceWheelGeometry
    let enabled: Set<Int>
    let centerEnabled: Bool
    let toolsIndex: Int?
    let canReorder: Bool
    let activeDrag: WorkspaceComposerDrag?
    let session: UUID
    let columnIDs: [String]
    let orderedIDs: [String]
    let names: [String]
    let hovered: (Int?, Bool) -> Void
    let click: (Int) -> Void
    let beginDrag: (Int) -> WorkspaceComposerDrag?
    let endDrag: () -> Void
    let dropHovered: (Int?) -> Void
    let receive: (String, String, Bool) -> Bool

    func makeNSView(context: Context) -> CursorView { CursorView() }
    func updateNSView(_ view: CursorView, context: Context) {
        view.count = count; view.geometry = geometry; view.enabled = enabled
        view.centerEnabled = centerEnabled; view.toolsIndex = toolsIndex
        view.canReorder = canReorder; view.isEnabled = context.environment.isEnabled
        view.activeDrag = activeDrag; view.session = session; view.columnIDs = columnIDs; view.names = names; view.orderedIDs = orderedIDs
        view.hovered = hovered; view.click = click; view.beginDrag = beginDrag
        view.endDrag = endDrag; view.dropHovered = dropHovered; view.receive = receive
    }

    class CursorView: NSView, NSDraggingSource {
        var count = 0
        var geometry = HeldWorkspaceWheelGeometry()
        var enabled: Set<Int> = []
        var centerEnabled = false
        var toolsIndex: Int?
        var canReorder = false
        var isEnabled = true
        var activeDrag: WorkspaceComposerDrag?
        var session = UUID()
        var columnIDs: [String] = []
        var names: [String] = []
        var orderedIDs: [String] = []
        var hovered: ((Int?, Bool) -> Void)?
        var click: ((Int) -> Void)?
        var beginDrag: ((Int) -> WorkspaceComposerDrag?)?
        var endDrag: (() -> Void)?
        var dropHovered: ((Int?) -> Void)?
        var receive: ((String, String, Bool) -> Bool)?
        private var press: (point: NSPoint, index: Int)?
        override var isFlipped: Bool { true }

        override init(frame: NSRect) {
            super.init(frame: frame)
            registerForDraggedTypes([.string])
            setAccessibilityElement(false)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }
        private func canvasPoint(_ point: NSPoint) -> CGPoint {
            CGPoint(x: point.x * geometry.diameter / max(1, bounds.width),
                    y: point.y * geometry.diameter / max(1, bounds.height))
        }
        private func sector(_ windowPoint: NSPoint) -> Int? {
            HeldWorkspaceWheelLayout.sector(at: canvasPoint(convert(windowPoint, from: nil)), count: count, geometry: geometry)
        }
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard isEnabled else { return nil }
            let local = canvasPoint(convert(point, from: superview))
            guard let index = HeldWorkspaceWheelLayout.sector(at: local, count: count, geometry: geometry),
                  enabled.contains(index) || canReorder else { return nil }
            if toolsIndex == index {
                let position = HeldWorkspaceWheelLayout.labelPoint(index: index, count: count, geometry: geometry)
                let tools = CGRect(x: position.x - 31, y: position.y + HeldWorkspaceWheelLayout.toolsOffset(count: count) - 13, width: 62, height: 26)
                if tools.contains(local) { return nil }
            }
            return self
        }
        override func mouseDown(with event: NSEvent) {
            press = isEnabled ? sector(event.locationInWindow).map { (event.locationInWindow, $0) } : nil
        }
        override func mouseUp(with event: NSEvent) {
            defer { press = nil }
            guard isEnabled, let press, enabled.contains(press.index), sector(event.locationInWindow) == press.index else { return }
            click?(press.index)
        }
        override func mouseDragged(with event: NSEvent) {
            guard isEnabled, canReorder, let press,
                  hypot(event.locationInWindow.x - press.point.x, event.locationInWindow.y - press.point.y) >= 4 else { return }
            self.press = nil
            guard let payload = beginDrag?(press.index) else { return }
            activeDrag = payload
            startDragging(payload: payload, name: names.indices.contains(press.index) ? names[press.index] : "", event: event)
        }
        // Separate initiation from gesture handling so the exact native threshold
        // and click suppression can be verified without starting a system drag.
        func startDragging(payload: WorkspaceComposerDrag, name: String, event: NSEvent) {
            let item = NSPasteboardItem()
            item.setString(payload.rawValue, forType: .string)
            let draggingItem = NSDraggingItem(pasteboardWriter: item)
            let preview = NSImage(size: NSSize(width: 180, height: 40), flipped: false) { rect in
                NSColor.windowBackgroundColor.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12).fill()
                let style = NSMutableParagraphStyle(); style.lineBreakMode = .byTruncatingTail; style.alignment = .center
                (name as NSString).draw(in: rect.insetBy(dx: 10, dy: 11), withAttributes: [
                    .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.labelColor, .paragraphStyle: style])
                return true
            }
            let point = convert(event.locationInWindow, from: nil)
            draggingItem.setDraggingFrame(NSRect(x: point.x - 90, y: point.y - 20, width: 180, height: 40), contents: preview)
            let drag = beginDraggingSession(with: [draggingItem], event: event, source: self)
            drag.animatesToStartingPositionsOnCancelOrFail = true
        }
        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            context == .withinApplication ? .move : []
        }
        func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            activeDrag = nil; press = nil; dropHovered?(nil); endDrag?()
        }

        func dropTarget(raw: String?, at point: NSPoint) -> HeldWheelReorderTarget? {
            guard isEnabled, canReorder, let index = sector(point), columnIDs.indices.contains(index) else { return nil }
            return HeldWheelReorderTarget.resolve(raw: raw, active: activeDrag, session: session,
                orderedIDs: orderedIDs, targetID: columnIDs[index])
        }
        private func updateDrop(_ sender: any NSDraggingInfo) -> NSDragOperation {
            guard dropTarget(raw: sender.draggingPasteboard.string(forType: .string), at: sender.draggingLocation) != nil else {
                dropHovered?(nil); return []
            }
            dropHovered?(sector(sender.draggingLocation)); return .move
        }
        override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { updateDrop(sender) }
        override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation { updateDrop(sender) }
        override func draggingExited(_ sender: (any NSDraggingInfo)?) { dropHovered?(nil) }
        override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
            dropTarget(raw: sender.draggingPasteboard.string(forType: .string), at: sender.draggingLocation) != nil
        }
        override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
            defer { dropHovered?(nil) }
            guard let target = dropTarget(raw: sender.draggingPasteboard.string(forType: .string), at: sender.draggingLocation) else { return false }
            return receive?(target.sourceID, target.targetID, target.after) ?? false
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited], owner: self))
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeInKeyWindow, .inVisibleRect, .cursorUpdate], owner: self))
            window?.acceptsMouseMovedEvents = true
        }
        override func mouseMoved(with event: NSEvent) { updateCursor(event) }
        override func mouseEntered(with event: NSEvent) { updateCursor(event) }
        override func cursorUpdate(with event: NSEvent) { updateCursor(event) }
        override func mouseExited(with event: NSEvent) {
            hovered?(nil, false)
            if window?.isVisible == true { NSCursor.arrow.set() }
        }
        private func updateCursor(_ event: NSEvent) {
            guard isEnabled else { return }
            let point = canvasPoint(convert(event.locationInWindow, from: nil))
            let isCenter = hypot(point.x - geometry.midpoint, point.y - geometry.midpoint) <= geometry.centerRadius
            let index = HeldWorkspaceWheelLayout.sector(at: point, count: count, geometry: geometry)
            hovered?(index, isCenter)
            guard window?.isVisible == true else { return }
            let actionable = isEnabled && ((isCenter && centerEnabled) || index.map { enabled.contains($0) || canReorder } == true)
            (actionable ? NSCursor.pointingHand : NSCursor.arrow).set()
        }
    }
}

struct HeldWheelReorderTarget: Equatable {
    let sourceID: String
    let targetID: String
    let after: Bool
    static func resolve(raw: String?, active: WorkspaceComposerDrag?, session: UUID, orderedIDs: [String], targetID: String) -> Self? {
        guard let raw, let active, active.session == session,
              WorkspaceComposerDrag(rawValue: raw) == active, active.desktop == nil,
              let sourceID = active.contextID, sourceID != targetID,
              let target = orderedIDs.firstIndex(of: targetID),
              let source = orderedIDs.firstIndex(of: sourceID) else { return nil }
        return Self(sourceID: sourceID, targetID: targetID, after: source < target)
    }
}
