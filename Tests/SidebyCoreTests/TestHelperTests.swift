import XCTest
@testable import SidebyCore

final class TestHelperTests: XCTestCase {
    func testInputEventFactoryBuildsHorizontalSwipe() {
        let event = InputEventFactory.horizontalSwipe(
            deltaX: 120,
            modifiers: [.option],
            timestamp: 10
        )

        XCTAssertEqual(event.type, .scrollWheel)
        XCTAssertEqual(event.deltaX, 120)
        XCTAssertEqual(event.deltaY, 0)
        XCTAssertEqual(event.modifierFlags, [.option])
        XCTAssertEqual(event.phase, .changed)
        XCTAssertEqual(event.timestamp, 10)
        XCTAssertFalse(event.isMomentum)
    }

    func testInputEventFactoryBuildsMomentumSwipe() {
        let event = InputEventFactory.horizontalSwipe(
            deltaX: -90,
            modifiers: [.option],
            timestamp: 11,
            isMomentum: true
        )

        XCTAssertEqual(event.deltaX, -90)
        XCTAssertTrue(event.isMomentum)
    }

    func testMockClockAdvancesDeterministically() {
        var clock = MockClock(start: 20)

        XCTAssertEqual(clock.now, 20)

        clock.advance(by: 0.35)

        XCTAssertEqual(clock.now, 20.35)
    }
}
