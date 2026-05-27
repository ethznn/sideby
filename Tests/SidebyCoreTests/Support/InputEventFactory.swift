@testable import SidebyCore

enum InputEventFactory {
    static func horizontalSwipe(
        deltaX: Double,
        modifiers: ModifierFlags = [],
        timestamp: Double = 0,
        isMomentum: Bool = false
    ) -> InputEvent {
        InputEvent(
            type: .scrollWheel,
            deltaX: deltaX,
            deltaY: 0,
            modifierFlags: modifiers,
            phase: .changed,
            timestamp: timestamp,
            isMomentum: isMomentum
        )
    }

    static func verticalSwipe(
        deltaY: Double,
        modifiers: ModifierFlags = [],
        timestamp: Double = 0,
        isMomentum: Bool = false
    ) -> InputEvent {
        InputEvent(
            type: .scrollWheel,
            deltaX: 0,
            deltaY: deltaY,
            modifierFlags: modifiers,
            phase: .changed,
            timestamp: timestamp,
            isMomentum: isMomentum
        )
    }
}
