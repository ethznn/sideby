import CoreGraphics
import Foundation
import XCTest
@testable import SidebyCore
@testable import SidebySystem

final class SerializedDockSwipeGestureTests: XCTestCase {
    func testNewEventFormatIsUsedOnlyOnMacOS27AndLater() {
        for version in [14, 15, 26] {
            XCTAssertFalse(SerializedDockSwipeGesture.isRequired(onMajorVersion: version))
        }
        XCTAssertTrue(SerializedDockSwipeGesture.isRequired(onMajorVersion: 27))
        XCTAssertTrue(SerializedDockSwipeGesture.isRequired(onMajorVersion: 28))
    }

    func testBothDirectionsHaveCompleteLocatedPhaseAndCompanionSequences() throws {
        let location = CGPoint(x: 840, y: 360)
        for command in [SwitchCommand.next, .previous] {
            let events = try XCTUnwrap(SerializedDockSwipeGesture.events(
                for: .make(for: command), location: location
            ))
            XCTAssertEqual(events.count, 6)
            XCTAssertEqual(events.map { $0.getIntegerValueField(CGEventField(rawValue: 55)!) }, [30, 29, 30, 29, 30, 29])
            let dockEvents = [events[0], events[2], events[4]]
            XCTAssertEqual(dockEvents.map { $0.getIntegerValueField(CGEventField(rawValue: 132)!) }, [1, 2, 4])
            for event in dockEvents {
                XCTAssertEqual(
                    event.getDoubleValueField(CGEventField(rawValue: 124)!),
                    command == .next ? -0.0001 : 0.0001,
                    accuracy: 0.0000000001,
                    "Each phase should preserve direction without a full-screen slide"
                )
            }
            XCTAssertEqual(events.map(\.location), Array(repeating: location, count: 6))
            for (event, phase) in zip(dockEvents, [Int64(1), 2, 4]) {
                let bytes = try XCTUnwrap(event.data) as Data
                let expectedPayload = SerializedDockSwipeGesture.payload(for: .make(for: command), phase: phase, timestamp: event.timestamp)
                XCTAssertNotNil(bytes.range(of: expectedPayload), "The posted event must retain its serialized IOHID payload")
            }
        }
    }

    func testPayloadContainsMatchingGestureAndTerminalVelocityRecords() {
        for command in [SwitchCommand.next, .previous] {
            for phase: Int64 in [1, 2, 4] {
                let payload = SerializedDockSwipeGesture.payload(for: .make(for: command), phase: phase, timestamp: 123)
                XCTAssertEqual(payload.count, phase == 4 ? 96 : 68)
                XCTAssertEqual(word(payload, 0), 123)
                XCTAssertEqual(word(payload, 24), phase == 4 ? 2 : 1)
                XCTAssertEqual(word(payload, 28), 40)
                XCTAssertEqual(word(payload, 32), 23)
                XCTAssertEqual(word(payload, 36), UInt32(phase) << 24)
                XCTAssertEqual(word(payload, 60), 0x0003_0001)
                XCTAssertEqual(
                    Int32(bitPattern: word(payload, 64)), command == .next ? -6 : 6,
                    "Near-zero travel must keep a nonzero direction after 16.16 encoding"
                )
                if phase == 4 {
                    XCTAssertEqual(word(payload, 68), 28)
                    XCTAssertEqual(word(payload, 72), 9)
                    XCTAssertEqual(word(payload, 80), 1)
                    XCTAssertEqual(Int32(bitPattern: word(payload, 84)), command == .next ? -655_294_464 : 655_294_464)
                }
            }
        }
    }

    func testFailureToCreateAnyEventDiscardsTheWholeGesture() {
        for failingCall in 1...6 {
            var calls = 0
            XCTAssertNil(SerializedDockSwipeGesture.events(for: .make(for: .next), location: nil, makeEvent: {
                calls += 1
                return calls == failingCall ? nil : CGEvent(source: nil)
            }))
        }
    }

    func testUnknownSerializedFormatCannotBeAugmented() {
        XCTAssertNil(SerializedDockSwipeGesture.appendingPayload(Data([1, 2]), to: Data([0, 0, 0, 3])))
        XCTAssertNil(SerializedDockSwipeGesture.appendingPayload(Data([1, 2]), to: Data()))
        XCTAssertEqual(SerializedDockSwipeGesture.appendingPayload(Data([1, 2]), to: Data([0, 0, 0, 2])), Data([0, 0, 0, 2, 0, 2, 0x10, 0x6D, 1, 2]))
    }

    private func word(_ data: Data, _ offset: Int) -> UInt32 {
        data[offset..<(offset + 4)].enumerated().reduce(0) { $0 | UInt32($1.element) << ($1.offset * 8) }
    }
}
