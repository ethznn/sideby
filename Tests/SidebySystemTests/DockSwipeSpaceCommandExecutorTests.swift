import XCTest
@testable import SidebyCore
@testable import SidebySystem

final class DockSwipeSpaceCommandExecutorTests: XCTestCase {
    func testDockSwipeDescriptorUsesSignedProgressAndVelocity() {
        let next = DockSwipeGestureDescriptor.make(for: .next)
        let previous = DockSwipeGestureDescriptor.make(for: .previous)

        XCTAssertEqual(next.progress, 1)
        XCTAssertEqual(next.velocityX, 9_999)
        XCTAssertEqual(previous.progress, -1)
        XCTAssertEqual(previous.velocityX, -9_999)
        XCTAssertEqual(next.beganPhase, 1)
        XCTAssertEqual(next.endedPhase, 4)
    }

    func testDockSwipeExecutorPostsOneDescriptor() {
        let poster = RecordingDockSwipePoster()
        let executor = DockSwipeSpaceCommandExecutor(poster: poster)

        XCTAssertTrue(executor.execute(.next))
        XCTAssertEqual(poster.descriptors, [.make(for: .next)])
    }

    func testCGDockPosterWritesVerifiedFieldsAndPostsBeganThenEndedToSessionTap() {
        let writer = RecordingCGDockSwipeEventWriter()
        let poster = CGDockSwipeEventPoster(
            writer: writer,
            hasOrRequestPostEventAccess: { true }
        )

        XCTAssertTrue(poster.post(.make(for: .next)))
        XCTAssertEqual(
            writer.integerWrites,
            [
                .init(field: 55, value: 30),
                .init(field: 110, value: 23),
                .init(field: 123, value: 1),
                .init(field: 132, value: 1),
                .init(field: 132, value: 4)
            ]
        )
        XCTAssertEqual(
            writer.doubleWrites,
            [
                .init(field: 124, value: 1),
                .init(field: 129, value: 9_999)
            ]
        )
        XCTAssertEqual(writer.postedTaps, [.session, .session])
    }
}

private final class RecordingDockSwipePoster: DockSwipeEventPosting, @unchecked Sendable {
    private(set) var descriptors: [DockSwipeGestureDescriptor] = []

    func post(_ descriptor: DockSwipeGestureDescriptor) -> Bool {
        descriptors.append(descriptor)
        return true
    }
}

private struct CGDockIntegerWrite: Equatable {
    let field: UInt32
    let value: Int64
}

private struct CGDockDoubleWrite: Equatable {
    let field: UInt32
    let value: Double
}

private final class RecordingCGDockSwipeEventWriter: CGDockSwipeEventWriting, CGDockSwipeEventWritingEvent, @unchecked Sendable {
    private(set) var integerWrites: [CGDockIntegerWrite] = []
    private(set) var doubleWrites: [CGDockDoubleWrite] = []
    private(set) var postedTaps: [DockSwipeEventTap] = []

    func makeEvent() -> (any CGDockSwipeEventWritingEvent)? {
        self
    }

    func setIntegerValue(field: UInt32, value: Int64) -> Bool {
        integerWrites.append(.init(field: field, value: value))
        return true
    }

    func setDoubleValue(field: UInt32, value: Double) -> Bool {
        doubleWrites.append(.init(field: field, value: value))
        return true
    }

    func post(tap: DockSwipeEventTap) -> Bool {
        postedTaps.append(tap)
        return true
    }
}
