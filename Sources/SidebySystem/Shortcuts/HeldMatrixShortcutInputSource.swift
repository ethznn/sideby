import Carbon
import CoreGraphics
import Foundation
import SidebyCore

@MainActor
public final class HeldMatrixShortcutInputSource {
    public enum Event: Equatable { case pressed, released, cancelled }
    private let registrar: any ContextKeyboardHotKeyRegistering
    private let keyIsDown: (UInt16) -> Bool
    private let modifiers: () -> ModifierFlags
    private let sessionIsInteractive: () -> Bool
    private let handler: (Event) -> Void
    private var shortcut: KeyboardShortcut?
    private var timer: Timer?
    public private(set) var isHeld = false
    private var didCancel = false

    public convenience init(handler: @escaping (Event) -> Void) {
        self.init(registrar: CarbonContextKeyboardHotKeyRegistrar(signature: 0x5342484D),
            keyIsDown: { CGEventSource.keyState(.combinedSessionState, key: $0) },
            modifiers: { EventTapInputNormalizer.modifierFlags(from: CGEventSource.flagsState(.combinedSessionState)) },
            sessionIsInteractive: {
                guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
                return session[kCGSessionOnConsoleKey as String] as? Bool == true
                    && session["CGSSessionScreenIsLocked"] as? Bool != true
            }, handler: handler)
    }

    init(registrar: any ContextKeyboardHotKeyRegistering, keyIsDown: @escaping (UInt16) -> Bool,
         modifiers: @escaping () -> ModifierFlags, sessionIsInteractive: @escaping () -> Bool,
         handler: @escaping (Event) -> Void) {
        self.registrar = registrar
        self.keyIsDown = keyIsDown
        self.modifiers = modifiers
        self.sessionIsInteractive = sessionIsInteractive
        self.handler = handler
    }

    isolated deinit { stop() }

    public func start(shortcut: KeyboardShortcut) -> Bool {
        guard self.shortcut == nil else { return self.shortcut == shortcut }
        guard registrar.installHandler({ [weak self] id, event in
            guard id == 1 else { return }
            self?.receive(event)
        }), registrar.register(id: 1, shortcut: shortcut) else {
            registrar.stop()
            return false
        }
        self.shortcut = shortcut
        // Recording a shortcut must not also open the matrix on key-repeat.
        if chordIsDown { isHeld = true; didCancel = true; beginPolling() }
        return true
    }

    public func stop() {
        registrar.stop()
        shortcut = nil
        endHold()
    }

    public var chordIsDown: Bool {
        guard let shortcut else { return false }
        return sessionIsInteractive() && keyIsDown(shortcut.keyCode)
            && modifiers().isSuperset(of: shortcut.modifiers)
    }

    private func receive(_ event: ContextKeyboardHotKeyEvent) {
        switch event {
        case .pressed:
            guard !isHeld, chordIsDown else { return }
            isHeld = true
            didCancel = false
            beginPolling()
            handler(.pressed)
        case .released:
            // Carbon can report a release when an extra modifier is pressed.
            checkHeldKeys()
        }
    }

    private func beginPolling() {
        let timer = Timer(timeInterval: 0.02, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkHeldKeys() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    public func checkHeldKeys() {
        guard isHeld else { return }
        guard chordIsDown else { endHold(); return }
        if keyIsDown(53), !didCancel { didCancel = true; handler(.cancelled) }
    }

    private func endHold() {
        timer?.invalidate()
        timer = nil
        guard isHeld else { return }
        isHeld = false
        didCancel = false
        handler(.released)
    }
}
