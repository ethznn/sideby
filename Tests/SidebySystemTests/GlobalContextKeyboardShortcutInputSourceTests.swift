import Carbon
import XCTest
@testable import SidebyCore
@testable import SidebySystem

@MainActor
final class GlobalContextKeyboardShortcutInputSourceTests: XCTestCase {
    func testCarbonEventDecoderRejectsForeignHotKeySignatures() {
        XCTAssertNil(
            ContextKeyboardCarbonEventDecoder.event(
                signature: OSType(0),
                eventKind: UInt32(kEventHotKeyPressed)
            )
        )
        XCTAssertEqual(
            ContextKeyboardCarbonEventDecoder.event(
                signature: ContextKeyboardCarbonEventDecoder.signature,
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            .pressed
        )
    }

    func testStartRegistersAllTwelveBindings() {
        let registrar = RecordingContextKeyboardHotKeyRegistrar()
        let source = GlobalContextKeyboardShortcutInputSource(
            registrar: registrar,
            handler: { _ in }
        )

        let result = source.start()

        XCTAssertEqual(result.registeredCommands, ContextKeyboardShortcutCatalog.bindings.map(\.command))
        XCTAssertEqual(result.failedCommands, [])
        XCTAssertEqual(registrar.registrations.map(\.shortcut), ContextKeyboardShortcutCatalog.bindings.map(\.shortcut))
        XCTAssertTrue(source.isRunning)
    }

    func testPressedDispatchesNumberAndArrowImmediately() {
        let registrar = RecordingContextKeyboardHotKeyRegistrar()
        var commands: [ContextKeyboardCommand] = []
        let source = GlobalContextKeyboardShortcutInputSource(
            registrar: registrar,
            handler: { commands.append($0) }
        )
        _ = source.start()

        registrar.emit(id: 1, event: .pressed)
        registrar.emit(id: 11, event: .pressed)
        registrar.emit(id: 12, event: .pressed)

        XCTAssertEqual(commands, [.activate(position: 1), .move(.previous), .move(.next)])
    }

    func testRepeatIsPerPhysicalKeyAndResetsOnRelease() {
        let registrar = RecordingContextKeyboardHotKeyRegistrar()
        var commands: [ContextKeyboardCommand] = []
        let source = GlobalContextKeyboardShortcutInputSource(
            registrar: registrar,
            handler: { commands.append($0) }
        )
        _ = source.start()

        registrar.emit(id: 1, event: .pressed)
        registrar.emit(id: 1, event: .pressed)
        registrar.emit(id: 12, event: .pressed)
        XCTAssertEqual(commands, [.activate(position: 1), .move(.next)])

        registrar.emit(id: 1, event: .released)
        registrar.emit(id: 12, event: .pressed)
        registrar.emit(id: 1, event: .pressed)
        XCTAssertEqual(commands, [.activate(position: 1), .move(.next), .activate(position: 1)])

        registrar.emit(id: 12, event: .released)
        registrar.emit(id: 12, event: .pressed)
        XCTAssertEqual(
            commands,
            [.activate(position: 1), .move(.next), .activate(position: 1), .move(.next)]
        )
    }

    func testPartialFailureKeepsSuccessfulBindings() {
        let registrar = RecordingContextKeyboardHotKeyRegistrar(failingIDs: [2, 11])
        var commands: [ContextKeyboardCommand] = []
        let source = GlobalContextKeyboardShortcutInputSource(
            registrar: registrar,
            handler: { commands.append($0) }
        )

        let result = source.start()
        registrar.emit(id: 1, event: .pressed)
        registrar.emit(id: 2, event: .pressed)
        registrar.emit(id: 12, event: .pressed)

        XCTAssertEqual(result.failedCommands, [.activate(position: 2), .move(.previous)])
        XCTAssertEqual(commands, [.activate(position: 1), .move(.next)])
        XCTAssertTrue(source.isRunning)
    }

    func testHandlerAndTotalRegistrationFailuresDoNotRun() {
        let installFailure = RecordingContextKeyboardHotKeyRegistrar(installsHandler: false)
        let installFailureSource = GlobalContextKeyboardShortcutInputSource(
            registrar: installFailure,
            handler: { _ in }
        )
        XCTAssertEqual(
            installFailureSource.start().failedCommands,
            ContextKeyboardShortcutCatalog.bindings.map(\.command)
        )
        XCTAssertFalse(installFailureSource.isRunning)

        let allRegistrationFailure = RecordingContextKeyboardHotKeyRegistrar(
            failingIDs: Set((1...12).map { UInt32($0) })
        )
        let allFailureSource = GlobalContextKeyboardShortcutInputSource(
            registrar: allRegistrationFailure,
            handler: { _ in }
        )
        XCTAssertEqual(
            allFailureSource.start().failedCommands,
            ContextKeyboardShortcutCatalog.bindings.map(\.command)
        )
        XCTAssertEqual(allRegistrationFailure.stopCount, 1)
        XCTAssertFalse(allFailureSource.isRunning)
    }

    func testStopUnregistersAndClearsState() {
        let registrar = RecordingContextKeyboardHotKeyRegistrar()
        let source = GlobalContextKeyboardShortcutInputSource(
            registrar: registrar,
            handler: { _ in }
        )
        _ = source.start()

        source.stop()

        XCTAssertEqual(registrar.stopCount, 1)
        XCTAssertFalse(source.isRunning)
    }

    func testStartIsIdempotentAfterPartialRegistrationFailure() {
        let registrar = RecordingContextKeyboardHotKeyRegistrar(failingIDs: [2, 11])
        let source = GlobalContextKeyboardShortcutInputSource(
            registrar: registrar,
            handler: { _ in }
        )

        let firstResult = source.start()
        let secondResult = source.start()

        XCTAssertEqual(secondResult, firstResult)
        XCTAssertEqual(registrar.installCount, 1)
        XCTAssertEqual(registrar.registrationAttempts, Array(1...12).map(UInt32.init))
    }

    func testStopIsIdempotentAndRestartResetsPressedKeys() {
        let registrar = RecordingContextKeyboardHotKeyRegistrar()
        var commands: [ContextKeyboardCommand] = []
        let source = GlobalContextKeyboardShortcutInputSource(
            registrar: registrar,
            handler: { commands.append($0) }
        )
        _ = source.start()
        registrar.emit(id: 1, event: .pressed)

        source.stop()
        source.stop()
        _ = source.start()
        registrar.emit(id: 1, event: .pressed)

        XCTAssertEqual(commands, [.activate(position: 1), .activate(position: 1)])
        XCTAssertEqual(registrar.installCount, 2)
        XCTAssertEqual(registrar.stopCount, 1)
        XCTAssertTrue(source.isRunning)
    }
}

private final class RecordingContextKeyboardHotKeyRegistrar: ContextKeyboardHotKeyRegistering {
    struct Registration: Equatable {
        let id: UInt32
        let shortcut: KeyboardShortcut
    }

    let installsHandler: Bool
    let failingIDs: Set<UInt32>
    var registrations: [Registration] = []
    var registrationAttempts: [UInt32] = []
    var installCount = 0
    var stopCount = 0
    private var handler: ((UInt32, ContextKeyboardHotKeyEvent) -> Void)?

    init(installsHandler: Bool = true, failingIDs: Set<UInt32> = []) {
        self.installsHandler = installsHandler
        self.failingIDs = failingIDs
    }

    func installHandler(
        _ handler: @escaping (UInt32, ContextKeyboardHotKeyEvent) -> Void
    ) -> Bool {
        installCount += 1
        guard installsHandler else { return false }
        self.handler = handler
        return true
    }

    func register(id: UInt32, shortcut: KeyboardShortcut) -> Bool {
        registrationAttempts.append(id)
        guard !failingIDs.contains(id) else { return false }
        registrations.append(Registration(id: id, shortcut: shortcut))
        return true
    }

    func stop() {
        stopCount += 1
        handler = nil
    }

    func emit(id: UInt32, event: ContextKeyboardHotKeyEvent) {
        handler?(id, event)
    }
}
