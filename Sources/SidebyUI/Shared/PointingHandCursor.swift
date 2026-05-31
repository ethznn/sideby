import AppKit
import SwiftUI

public extension View {
    func pointingHandCursor(_ isEnabled: Bool = true) -> some View {
        modifier(PointingHandCursorModifier(isEnabled: isEnabled))
    }
}

private struct PointingHandCursorModifier: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content.overlay {
            if isEnabled {
                PointingHandCursorRect()
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct PointingHandCursorRect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        PointingHandCursorNSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.window?.invalidateCursorRects(for: nsView)
    }
}

private final class PointingHandCursorNSView: NSView {
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
