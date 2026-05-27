import CoreGraphics
import Foundation
import SidebyCore

public enum EventTapInputNormalizer {
    public static func normalizedScroll(
        deltaX: Double,
        deltaY: Double,
        flags: CGEventFlags,
        timestamp: Double,
        isMomentum: Bool
    ) -> InputEvent {
        InputEvent(
            type: .scrollWheel,
            deltaX: deltaX,
            deltaY: deltaY,
            modifierFlags: modifierFlags(from: flags),
            phase: .changed,
            timestamp: timestamp,
            isMomentum: isMomentum
        )
    }

    public static func modifierFlags(from flags: CGEventFlags) -> ModifierFlags {
        var modifiers: ModifierFlags = []

        if flags.contains(.maskShift) {
            modifiers.insert(.shift)
        }
        if flags.contains(.maskControl) {
            modifiers.insert(.control)
        }
        if flags.contains(.maskAlternate) {
            modifiers.insert(.option)
        }
        if flags.contains(.maskCommand) {
            modifiers.insert(.command)
        }
        if flags.contains(.maskSecondaryFn) {
            modifiers.insert(.function)
        }

        return modifiers
    }

    public static func modifierFlag(forKeyCode keyCode: CGKeyCode) -> ModifierFlags? {
        switch keyCode {
        case 56, 60:
            return .shift
        case 59, 62:
            return .control
        case 58, 61:
            return .option
        case 55, 54:
            return .command
        case 63:
            return .function
        default:
            return nil
        }
    }

    public static func preferredScrollDelta(discrete: Double, point: Double, fixed: Double) -> Double {
        if point != 0 {
            return point
        }
        if fixed != 0 {
            return fixed
        }
        return discrete
    }

    public static func isMomentumScroll(momentumPhase: Int64) -> Bool {
        momentumPhase != 0
    }

    public static func inputEvent(
        type: CGEventType,
        event: CGEvent,
        timestamp: Double
    ) -> InputEvent? {
        switch type {
        case .scrollWheel:
            return normalizedScroll(
                deltaX: preferredScrollDelta(
                    discrete: event.getDoubleValueField(.scrollWheelEventDeltaAxis2),
                    point: event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2),
                    fixed: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
                ),
                deltaY: preferredScrollDelta(
                    discrete: event.getDoubleValueField(.scrollWheelEventDeltaAxis1),
                    point: event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1),
                    fixed: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
                ),
                flags: event.flags,
                timestamp: timestamp,
                isMomentum: isMomentumScroll(
                    momentumPhase: event.getIntegerValueField(.scrollWheelEventMomentumPhase)
                )
            )
        case .flagsChanged:
            return InputEvent(
                type: .flagsChanged,
                deltaX: 0,
                deltaY: 0,
                modifierFlags: modifierFlags(from: event.flags),
                phase: .none,
                timestamp: timestamp,
                isMomentum: false
            )
        default:
            return nil
        }
    }
}

public final class EventTapInputSource {
    public typealias Handler = (InputEvent) -> Void

    private let handler: Handler

    public init(handler: @escaping Handler) {
        self.handler = handler
    }

    public func handle(type: CGEventType, event: CGEvent, timestamp: Double) {
        guard let inputEvent = EventTapInputNormalizer.inputEvent(
            type: type,
            event: event,
            timestamp: timestamp
        ) else {
            return
        }

        handler(inputEvent)
    }
}

public enum GlobalEventTapStartResult: Equatable, Sendable {
    case started
    case alreadyRunning
    case failedToCreateTap
}

public final class GlobalEventTapInputSource {
    private let inputSource: EventTapInputSource
    private let suppressedScrollModifiers: ModifierFlags?
    private let suppressedModifierFlags: ModifierFlags?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    public init(
        suppressesOptionScrollEvents: Bool = false,
        handler: @escaping EventTapInputSource.Handler
    ) {
        self.suppressedScrollModifiers = suppressesOptionScrollEvents ? [.option] : nil
        self.suppressedModifierFlags = nil
        self.inputSource = EventTapInputSource(handler: handler)
    }

    public init(
        suppressedScrollModifiers: ModifierFlags?,
        suppressedModifierFlags: ModifierFlags? = nil,
        handler: @escaping EventTapInputSource.Handler
    ) {
        self.suppressedScrollModifiers = suppressedScrollModifiers
        self.suppressedModifierFlags = suppressedModifierFlags
        self.inputSource = EventTapInputSource(handler: handler)
    }

    deinit {
        stop()
    }

    public var isRunning: Bool {
        eventTap != nil
    }

    public func start() -> GlobalEventTapStartResult {
        guard eventTap == nil else {
            return .alreadyRunning
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: shouldUseDefaultTap ? .defaultTap : .listenOnly,
            eventsOfInterest: Self.eventMask,
            callback: Self.callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return .failedToCreateTap
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        return .started
    }

    private var shouldUseDefaultTap: Bool {
        suppressedScrollModifiers != nil || suppressedModifierFlags != nil
    }

    public func stop() {
        guard let tap = eventTap else {
            return
        }

        CGEvent.tapEnable(tap: tap, enable: false)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private static let eventMask = mask(for: .scrollWheel) | mask(for: .flagsChanged)

    private static func mask(for type: CGEventType) -> CGEventMask {
        CGEventMask(1) << CGEventMask(type.rawValue)
    }

    public static func shouldSuppressOptionScroll(type: CGEventType, flags: CGEventFlags) -> Bool {
        shouldSuppressScroll(type: type, flags: flags, requiredModifiers: [.option])
    }

    public static func shouldSuppressScroll(
        type: CGEventType,
        flags: CGEventFlags,
        requiredModifiers: ModifierFlags
    ) -> Bool {
        guard type == .scrollWheel, !requiredModifiers.isEmpty else {
            return false
        }

        let modifiers = EventTapInputNormalizer.modifierFlags(from: flags)
        return InputModifierMatchPolicy.gestureModifiersMatch(
            eventModifiers: modifiers,
            requiredModifiers: requiredModifiers
        )
    }

    public static func shouldSuppressModifierFlagChange(
        type: CGEventType,
        keyCode: CGKeyCode,
        requiredModifiers: ModifierFlags
    ) -> Bool {
        guard type == .flagsChanged,
              let modifier = EventTapInputNormalizer.modifierFlag(forKeyCode: keyCode)
        else {
            return false
        }

        return requiredModifiers.contains(modifier)
    }

    private static let callback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else {
            return Unmanaged.passUnretained(event)
        }

        let eventTapInputSource = Unmanaged<GlobalEventTapInputSource>
            .fromOpaque(refcon)
            .takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap = eventTapInputSource.eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        eventTapInputSource.inputSource.handle(
            type: type,
            event: event,
            timestamp: ProcessInfo.processInfo.systemUptime
        )
        if let suppressedModifierFlags = eventTapInputSource.suppressedModifierFlags,
           shouldSuppressModifierFlagChange(
               type: type,
               keyCode: CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)),
               requiredModifiers: suppressedModifierFlags
           ) {
            return nil
        }
        if let suppressedScrollModifiers = eventTapInputSource.suppressedScrollModifiers,
           shouldSuppressScroll(type: type, flags: event.flags, requiredModifiers: suppressedScrollModifiers) {
            return nil
        }
        return Unmanaged.passUnretained(event)
    }
}
