import CoreGraphics
import Foundation

/// macOS 27 requires an IOHID payload and a companion gesture event for each
/// Dock-swipe phase. Keep the older event format unchanged on earlier systems.
/// Payload format adapted from noswoosh (MIT) and joshuarli/iss (ISC).
/// See Resources/ThirdPartyNotices.txt for the upstream notices.
enum SerializedDockSwipeGesture {
    // The terminal velocity commits the move; a tiny nonzero travel avoids the
    // full-screen slide while keeping direction through 16.16 serialization.
    private static let travelFraction = 0.0001

    static func isRequired(onMajorVersion version: Int) -> Bool { version >= 27 }

    static func events(
        for descriptor: DockSwipeGestureDescriptor,
        location: CGPoint?,
        makeEvent: () -> CGEvent? = { CGEvent(source: nil) }
    ) -> [CGEvent]? {
        var result: [CGEvent] = []
        // Prepare every phase before posting anything: an incomplete sequence
        // can leave the Dock in the middle of a gesture.
        for phase: Int64 in [descriptor.beganPhase, 2, descriptor.endedPhase] {
            guard let dock = makeEvent(), let companion = makeEvent() else { return nil }
            if let location {
                dock.location = location
                companion.location = location
            }
            dock.setIntegerValueField(field(55), value: descriptor.dockControlType)
            dock.setIntegerValueField(field(110), value: descriptor.hidType)
            dock.setIntegerValueField(field(123), value: descriptor.motion)
            dock.setIntegerValueField(field(132), value: phase)
            // The serialized gesture uses the opposite direction convention.
            dock.setDoubleValueField(field(124), value: -descriptor.progress * travelFraction)
            dock.setDoubleValueField(field(125), value: 0.1)
            if phase == descriptor.endedPhase {
                dock.setDoubleValueField(field(129), value: -descriptor.velocityX)
            }
            if dock.timestamp == 0 { dock.timestamp = mach_absolute_time() }
            guard let serialized = dock.data,
                  let augmented = appendingPayload(
                    payload(for: descriptor, phase: phase, timestamp: dock.timestamp),
                    to: serialized as Data
                  ),
                  let event = CGEvent(withDataAllocator: nil, data: augmented as CFData)
            else { return nil }
            companion.setIntegerValueField(field(55), value: 29)
            result.append(contentsOf: [event, companion])
        }
        return result
    }

    static func post(_ descriptor: DockSwipeGestureDescriptor, at location: CGPoint?) -> Bool {
        guard let events = events(for: descriptor, location: location) else { return false }
        for event in events { event.post(tap: .cgSessionEventTap) }
        return true
    }

    static func payload(for descriptor: DockSwipeGestureDescriptor, phase: Int64, timestamp: UInt64) -> Data {
        let terminal = phase == descriptor.endedPhase
        var data = Data()
        // IOHIDSystemQueueElementHeader: timestamp, sender, options,
        // attribute length, and number of records.
        append(timestamp, to: &data)
        append(UInt64(0), to: &data)
        append(UInt32(0), to: &data)
        append(UInt32(0), to: &data)
        append(UInt32(terminal ? 2 : 1), to: &data)
        // Fluid-touch gesture record, including phase in its options byte.
        append(UInt32(40), to: &data)
        append(UInt32(descriptor.hidType), to: &data)
        append((UInt32(truncatingIfNeeded: phase) & 0xFF) << 24, to: &data)
        append(UInt32(0), to: &data)
        append(fixed(0.1), to: &data)
        append(Int32(0), to: &data)
        append(Int32(0), to: &data)
        append(UInt32(0), to: &data)
        append(UInt16(descriptor.motion), to: &data)
        append(UInt16(3), to: &data)
        append(fixed(-descriptor.progress * travelFraction), to: &data)
        if terminal {
            // A terminal velocity record commits the swipe on macOS 27.
            append(UInt32(28), to: &data)
            append(UInt32(9), to: &data)
            append(UInt32(0), to: &data)
            append(UInt32(1), to: &data)
            append(fixed(-descriptor.velocityX), to: &data)
            append(Int32(0), to: &data)
            append(Int32(0), to: &data)
        }
        return data
    }

    static func appendingPayload(_ payload: Data, to serialized: Data) -> Data? {
        guard serialized.starts(with: [0, 0, 0, 2]), payload.count <= Int(UInt16.max) else { return nil }
        var data = serialized
        // CGEvent serialized fields use a big-endian length and field tag;
        // the IOHID structures inside the field use little-endian integers.
        let count = UInt16(payload.count)
        data.append(contentsOf: [UInt8(count >> 8), UInt8(count & 0xFF), 0x10, 0x6D])
        data.append(payload)
        return data
    }

    private static func field(_ value: UInt32) -> CGEventField { CGEventField(rawValue: value)! }

    private static func fixed(_ value: Double) -> Int32 {
        let encoded = Int32(truncatingIfNeeded: Int64(value * 65_536))
        return encoded == 0 && value != 0 ? (value > 0 ? 1 : -1) : encoded
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
}
