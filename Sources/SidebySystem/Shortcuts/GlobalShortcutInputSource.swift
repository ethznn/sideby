import Carbon
import CoreGraphics
import Foundation
import SidebyCore

public enum KeyboardShortcutInputNormalizer {
    public static func keyboardEvent(type: CGEventType, event: CGEvent) -> KeyboardEvent? {
        guard type == .keyDown else {
            return nil
        }

        return KeyboardEvent(
            keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
            modifiers: EventTapInputNormalizer.modifierFlags(from: event.flags)
        )
    }

}

public final class GlobalShortcutInputSource {
    public typealias CommandHandler = (SwitchCommand) -> Void

    private let shortcutInputSource: ShortcutInputSource
    private let commandHandler: CommandHandler
    private let releaseHandler: CommandHandler?
    private let suppressedModifierFlags: ModifierFlags?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var eventHandler: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var commandsByHotKeyID: [UInt32: SwitchCommand] = [:]

    public init(
        shortcutInputSource: ShortcutInputSource,
        suppressedModifierFlags: ModifierFlags? = nil,
        commandHandler: @escaping CommandHandler,
        releaseHandler: CommandHandler? = nil
    ) {
        self.shortcutInputSource = shortcutInputSource
        self.suppressedModifierFlags = suppressedModifierFlags
        self.commandHandler = commandHandler
        self.releaseHandler = releaseHandler
    }

    deinit {
        stop()
    }

    public var isRunning: Bool {
        eventTap != nil || !hotKeyRefs.isEmpty
    }

    public func start() -> GlobalEventTapStartResult {
        guard eventTap == nil, hotKeyRefs.isEmpty else {
            return .alreadyRunning
        }

        if startHotKeys() {
            return .started
        }

        return startEventTapFallback()
    }

    private func startHotKeys() -> Bool {
        var specs = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            )
        ]
        var handlerRef: EventHandlerRef?
        let handlerStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            Self.hotKeyHandler,
            specs.count,
            &specs,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        guard handlerStatus == noErr, let handlerRef else {
            return false
        }

        eventHandler = handlerRef
        guard register(shortcut: shortcutInputSource.previousShortcut, command: .previous, id: 1),
              register(shortcut: shortcutInputSource.nextShortcut, command: .next, id: 2)
        else {
            stop()
            return false
        }

        return true
    }

    private func register(shortcut: KeyboardShortcut, command: SwitchCommand, id: UInt32) -> Bool {
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: id)
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            Self.carbonModifiers(from: shortcut.modifiers),
            hotKeyID,
            GetEventDispatcherTarget(),
            OptionBits(0),
            &hotKeyRef
        )

        guard status == noErr, let hotKeyRef else {
            return false
        }

        hotKeyRefs.append(hotKeyRef)
        commandsByHotKeyID[id] = command
        return true
    }

    private func startEventTapFallback() -> GlobalEventTapStartResult {
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
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

    public func stop() {
        for hotKeyRef in hotKeyRefs {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRefs = []
        commandsByHotKeyID = [:]

        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            }
        }

        eventTap = nil
        runLoopSource = nil
    }

    @discardableResult
    public func handle(type: CGEventType, event: CGEvent) -> Bool {
        guard
            let keyboardEvent = KeyboardShortcutInputNormalizer.keyboardEvent(type: type, event: event),
            let command = shortcutInputSource.command(for: keyboardEvent)
        else {
            return false
        }

        commandHandler(command)
        return true
    }

    @discardableResult
    public func handleRelease(type: CGEventType, event: CGEvent) -> Bool {
        guard
            type == .keyUp,
            let keyboardEvent = KeyboardShortcutInputNormalizer.keyboardEvent(type: .keyDown, event: event),
            let command = shortcutInputSource.command(for: keyboardEvent)
        else {
            return false
        }

        releaseHandler?(command)
        return releaseHandler != nil
    }

    public static func shouldSuppressShortcutEvent(didMatchShortcut: Bool) -> Bool {
        didMatchShortcut
    }

    public static func shouldSuppressModifierFlagChange(
        type: CGEventType,
        keyCode: CGKeyCode,
        requiredModifiers: ModifierFlags
    ) -> Bool {
        GlobalEventTapInputSource.shouldSuppressModifierFlagChange(
            type: type,
            keyCode: keyCode,
            requiredModifiers: requiredModifiers
        )
    }

    private static let eventMask = mask(for: .keyDown) | mask(for: .keyUp) | mask(for: .flagsChanged)
    private static let hotKeySignature = OSType(
        UInt32(ascii: "S") << 24 |
            UInt32(ascii: "B") << 16 |
            UInt32(ascii: "S") << 8 |
            UInt32(ascii: "H")
    )

    private static func mask(for type: CGEventType) -> CGEventMask {
        CGEventMask(1) << CGEventMask(type.rawValue)
    }

    private static let callback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else {
            return Unmanaged.passUnretained(event)
        }

        let inputSource = Unmanaged<GlobalShortcutInputSource>
            .fromOpaque(refcon)
            .takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap = inputSource.eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if let suppressedModifierFlags = inputSource.suppressedModifierFlags,
           shouldSuppressModifierFlagChange(
               type: type,
               keyCode: CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)),
               requiredModifiers: suppressedModifierFlags
           ) {
            return nil
        }

        let didMatchShortcut: Bool
        if type == .keyUp {
            didMatchShortcut = inputSource.handleRelease(type: type, event: event)
        } else {
            didMatchShortcut = inputSource.handle(type: type, event: event)
        }
        if shouldSuppressShortcutEvent(didMatchShortcut: didMatchShortcut) {
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    private static let hotKeyHandler: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else {
            return noErr
        }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr else {
            return status
        }

        let inputSource = Unmanaged<GlobalShortcutInputSource>
            .fromOpaque(userData)
            .takeUnretainedValue()
        guard let command = inputSource.commandsByHotKeyID[hotKeyID.id] else {
            return noErr
        }

        switch GetEventKind(event) {
        case UInt32(kEventHotKeyPressed):
            inputSource.commandHandler(command)
        case UInt32(kEventHotKeyReleased):
            inputSource.releaseHandler?(command)
        default:
            break
        }

        return noErr
    }

    private static func carbonModifiers(from modifiers: ModifierFlags) -> UInt32 {
        var carbonModifiers: UInt32 = 0
        if modifiers.contains(.shift) {
            carbonModifiers |= UInt32(shiftKey)
        }
        if modifiers.contains(.control) {
            carbonModifiers |= UInt32(controlKey)
        }
        if modifiers.contains(.option) {
            carbonModifiers |= UInt32(optionKey)
        }
        if modifiers.contains(.command) {
            carbonModifiers |= UInt32(cmdKey)
        }
        return carbonModifiers
    }
}

private extension UInt32 {
    init(ascii character: Character) {
        self = character.unicodeScalars.first.map(UInt32.init) ?? 0
    }
}
