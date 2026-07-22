import Carbon
import CoreGraphics
import Foundation
import SidebyCore

@MainActor
public final class ContextKeyboardModifierReleaseWaiter {
    typealias ScheduledCheck = @MainActor @Sendable () -> Void

    private let currentModifiers: @MainActor @Sendable () -> ModifierFlags
    private let scheduleNextCheck: @MainActor @Sendable (@escaping ScheduledCheck) -> Void

    public convenience init(pollInterval: TimeInterval = 0.015) {
        self.init(
            currentModifiers: {
                EventTapInputNormalizer.modifierFlags(
                    from: CGEventSource.flagsState(.combinedSessionState)
                )
            },
            scheduleNextCheck: { check in
                DispatchQueue.main.asyncAfter(deadline: .now() + pollInterval) {
                    check()
                }
            }
        )
    }

    init(
        currentModifiers: @escaping @MainActor @Sendable () -> ModifierFlags,
        scheduleNextCheck: @escaping @MainActor @Sendable (@escaping ScheduledCheck) -> Void
    ) {
        self.currentModifiers = currentModifiers
        self.scheduleNextCheck = scheduleNextCheck
    }

    public func waitUntilReleased(
        triggerModifiers: ModifierFlags,
        completion: @escaping @MainActor @Sendable () -> Void
    ) {
        guard !InputModifierReleasePolicy.didReleaseAllTriggerModifiers(
            currentModifiers: currentModifiers(),
            triggerModifiers: triggerModifiers
        ) else {
            completion()
            return
        }

        scheduleNextCheck { [weak self] in
            self?.waitUntilReleased(
                triggerModifiers: triggerModifiers,
                completion: completion
            )
        }
    }
}

public struct ContextKeyboardShortcutStartResult: Equatable, Sendable {
    public let registeredCommands: [ContextKeyboardCommand]
    public let failedCommands: [ContextKeyboardCommand]

    public init(
        registeredCommands: [ContextKeyboardCommand],
        failedCommands: [ContextKeyboardCommand]
    ) {
        self.registeredCommands = registeredCommands
        self.failedCommands = failedCommands
    }
}

public enum ContextKeyboardShortcutInputEvent: Equatable, Sendable {
    case pressed(ContextKeyboardCommand)
    case released(ContextKeyboardCommand)
}

enum ContextKeyboardHotKeyEvent: Equatable, Sendable {
    case pressed
    case released
}

enum ContextKeyboardCarbonEventDecoder {
    static let signature = OSType(
        UInt32(contextKeyboardASCII: "S") << 24 |
            UInt32(contextKeyboardASCII: "B") << 16 |
            UInt32(contextKeyboardASCII: "K") << 8 |
            UInt32(contextKeyboardASCII: "L")
    )

    static func event(
        signature: OSType,
        eventKind: UInt32
    ) -> ContextKeyboardHotKeyEvent? {
        guard signature == Self.signature else { return nil }

        switch eventKind {
        case UInt32(kEventHotKeyPressed):
            return .pressed
        case UInt32(kEventHotKeyReleased):
            return .released
        default:
            return nil
        }
    }
}

@MainActor
protocol ContextKeyboardHotKeyRegistering: AnyObject {
    func installHandler(
        _ handler: @escaping (UInt32, ContextKeyboardHotKeyEvent) -> Void
    ) -> Bool
    func register(id: UInt32, shortcut: KeyboardShortcut) -> Bool
    func stop()
}

@MainActor
public final class GlobalContextKeyboardShortcutInputSource {
    public typealias EventHandler = (ContextKeyboardShortcutInputEvent) -> Void
    public typealias CommandHandler = (ContextKeyboardCommand) -> Void

    private let registrar: any ContextKeyboardHotKeyRegistering
    private let handler: EventHandler
    private var commandsByID: [UInt32: ContextKeyboardCommand] = [:]
    private var activeIDs: Set<UInt32> = []
    private var currentStartResult: ContextKeyboardShortcutStartResult?
    private var didInstallHandler = false

    public convenience init(handler: @escaping EventHandler) {
        self.init(registrar: CarbonContextKeyboardHotKeyRegistrar(), handler: handler)
    }

    public convenience init(_ handler: @escaping CommandHandler) {
        self.init(handler: { event in
            guard case let .pressed(command) = event else { return }
            handler(command)
        })
    }

    init(
        registrar: any ContextKeyboardHotKeyRegistering,
        handler: @escaping EventHandler
    ) {
        self.registrar = registrar
        self.handler = handler
    }

    isolated deinit {
        stop()
    }

    public var isRunning: Bool {
        !commandsByID.isEmpty
    }

    @discardableResult
    public func start() -> ContextKeyboardShortcutStartResult {
        if let currentStartResult {
            return currentStartResult
        }

        let allCommands = ContextKeyboardShortcutCatalog.bindings.map(\.command)
        guard registrar.installHandler({ [weak self] id, event in
            self?.handle(id: id, event: event)
        }) else {
            return ContextKeyboardShortcutStartResult(
                registeredCommands: [],
                failedCommands: allCommands
            )
        }

        didInstallHandler = true
        var failedCommands: [ContextKeyboardCommand] = []
        for (offset, binding) in ContextKeyboardShortcutCatalog.bindings.enumerated() {
            let id = UInt32(offset + 1)
            if registrar.register(id: id, shortcut: binding.shortcut) {
                commandsByID[id] = binding.command
            } else {
                failedCommands.append(binding.command)
            }
        }

        let result = ContextKeyboardShortcutStartResult(
            registeredCommands: registeredCommands,
            failedCommands: failedCommands
        )
        guard !commandsByID.isEmpty else {
            registrar.stop()
            didInstallHandler = false
            return result
        }

        currentStartResult = result
        return result
    }

    public func stop() {
        guard didInstallHandler else { return }

        registrar.stop()
        commandsByID = [:]
        activeIDs = []
        currentStartResult = nil
        didInstallHandler = false
    }

    private var registeredCommands: [ContextKeyboardCommand] {
        commandsByID.keys.sorted().compactMap { commandsByID[$0] }
    }

    private func handle(id: UInt32, event: ContextKeyboardHotKeyEvent) {
        guard let command = commandsByID[id] else { return }

        switch event {
        case .pressed:
            guard activeIDs.insert(id).inserted else { return }
            handler(.pressed(command))
        case .released:
            guard activeIDs.remove(id) != nil else { return }
            handler(.released(command))
        }
    }
}

@MainActor
private final class CarbonContextKeyboardHotKeyRegistrar: ContextKeyboardHotKeyRegistering {
    private var handler: ((UInt32, ContextKeyboardHotKeyEvent) -> Void)?
    private var eventHandler: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef] = []

    isolated deinit {
        stop()
    }

    func installHandler(
        _ handler: @escaping (UInt32, ContextKeyboardHotKeyEvent) -> Void
    ) -> Bool {
        guard eventHandler == nil else { return false }

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
        var installedHandler: EventHandlerRef?
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            Self.callback,
            specs.count,
            &specs,
            Unmanaged.passUnretained(self).toOpaque(),
            &installedHandler
        )
        guard status == noErr, let installedHandler else {
            if let installedHandler {
                RemoveEventHandler(installedHandler)
            }
            return false
        }

        self.handler = handler
        eventHandler = installedHandler
        return true
    }

    func register(id: UInt32, shortcut: KeyboardShortcut) -> Bool {
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(
            signature: ContextKeyboardCarbonEventDecoder.signature,
            id: id
        )
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            Self.carbonModifiers(from: shortcut.modifiers),
            hotKeyID,
            GetEventDispatcherTarget(),
            OptionBits(0),
            &hotKeyRef
        )
        guard status == noErr, let hotKeyRef else {
            if let hotKeyRef {
                UnregisterEventHotKey(hotKeyRef)
            }
            return false
        }

        hotKeyRefs.append(hotKeyRef)
        return true
    }

    func stop() {
        for hotKeyRef in hotKeyRefs {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRefs = []

        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        handler = nil
    }

    private nonisolated static let callback: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return noErr }
        guard Thread.isMainThread else { return OSStatus(eventNotHandledErr) }

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
        guard status == noErr else { return status }

        guard let hotKeyEvent = ContextKeyboardCarbonEventDecoder.event(
            signature: hotKeyID.signature,
            eventKind: GetEventKind(event)
        ) else {
            return OSStatus(eventNotHandledErr)
        }

        let id = hotKeyID.id
        let registrar = Unmanaged<CarbonContextKeyboardHotKeyRegistrar>
            .fromOpaque(userData)
            .takeUnretainedValue()
        return MainActor.assumeIsolated {
            registrar.handler?(id, hotKeyEvent)
            return noErr
        }
    }

    private static func carbonModifiers(from modifiers: ModifierFlags) -> UInt32 {
        var value: UInt32 = 0
        if modifiers.contains(.shift) { value |= UInt32(shiftKey) }
        if modifiers.contains(.control) { value |= UInt32(controlKey) }
        if modifiers.contains(.option) { value |= UInt32(optionKey) }
        if modifiers.contains(.command) { value |= UInt32(cmdKey) }
        return value
    }
}

private extension UInt32 {
    init(contextKeyboardASCII character: Character) {
        self = character.unicodeScalars.first.map(UInt32.init) ?? 0
    }
}
