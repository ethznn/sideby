import AppKit
import SwiftUI

public enum NativeInteractionCursor {
    case pointingHand
    case openHand
    case resizeLeftRight

    var nsCursor: NSCursor {
        switch self {
        case .pointingHand: .pointingHand
        case .openHand: .openHand
        case .resizeLeftRight: .resizeLeftRight
        }
    }
}

public extension View {
    func pointingHandCursor(_ isEnabled: Bool = true) -> some View {
        interactionCursor(.pointingHand, isEnabled: isEnabled)
    }

    func interactionCursor(_ cursor: NativeInteractionCursor, isEnabled: Bool = true) -> some View {
        modifier(InteractionCursorModifier(cursor: cursor, isEnabled: isEnabled))
    }
}

private struct InteractionCursorModifier: ViewModifier {
    let cursor: NativeInteractionCursor
    let isEnabled: Bool
    @Environment(\.isEnabled) private var environmentEnabled

    func body(content: Content) -> some View {
        content.overlay {
            if isEnabled && environmentEnabled {
                InteractionCursorRect(cursor: cursor).allowsHitTesting(false)
            }
        }
    }
}

private struct InteractionCursorRect: NSViewRepresentable {
    let cursor: NativeInteractionCursor

    func makeNSView(context: Context) -> InteractionCursorNSView {
        InteractionCursorNSView(cursor: cursor)
    }

    func updateNSView(_ nsView: InteractionCursorNSView, context: Context) {
        nsView.cursor = cursor
        nsView.window?.invalidateCursorRects(for: nsView)
    }
}

private final class InteractionCursorNSView: NSView {
    var cursor: NativeInteractionCursor
    private var cursorTrackingArea: NSTrackingArea?

    init(cursor: NativeInteractionCursor) {
        self.cursor = cursor
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override func resetCursorRects() {
        addCursorRect(visibleRect, cursor: cursor.nsCursor)
    }

    override func updateTrackingAreas() {
        if let cursorTrackingArea { removeTrackingArea(cursorTrackingArea) }
        super.updateTrackingAreas()
        // The menu is a nonactivating NSPanel. Cursor rectangles alone do not
        // cover that case while another app is active.
        let area = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        cursorTrackingArea = area
        window?.acceptsMouseMovedEvents = true
    }

    override func mouseEntered(with event: NSEvent) { cursor.nsCursor.set() }
    override func mouseMoved(with event: NSEvent) { cursor.nsCursor.set() }
    override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
