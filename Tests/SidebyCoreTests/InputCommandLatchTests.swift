import XCTest
@testable import SidebyCore

final class InputCommandLatchTests: XCTestCase {
    func testDefaultCooldownIsShortEnoughForFollowUpInput() {
        XCTAssertEqual(InputCommandLatch.defaultCooldownInterval, 0.08)
        XCTAssertEqual(InputCommandLatch().cooldownInterval, 0.08)
    }

    func testAcceptsOnlyOnePendingCommand() {
        var latch = InputCommandLatch(cooldownInterval: 0.7)

        XCTAssertTrue(latch.accept(.next, source: .swipe, at: 1.0))
        XCTAssertFalse(latch.accept(.previous, source: .swipe, at: 1.1))
        XCTAssertEqual(latch.releasePending(source: .swipe), .next)
    }

    func testReleaseIgnoresDifferentSource() {
        var latch = InputCommandLatch(cooldownInterval: 0.7)

        XCTAssertTrue(latch.accept(.next, source: .keyboard, at: 1.0))
        XCTAssertNil(latch.releasePending(source: .swipe))
        XCTAssertEqual(latch.releasePending(source: .keyboard), .next)
    }

    func testCooldownBlocksInputUntilItExpires() {
        var latch = InputCommandLatch(cooldownInterval: 0.7)

        XCTAssertTrue(latch.accept(.next, source: .swipe, at: 1.0))
        XCTAssertEqual(latch.releasePending(source: .swipe), .next)
        latch.finishSwitch(at: 1.2)

        XCTAssertFalse(latch.allowsInput(at: 1.8))
        XCTAssertTrue(latch.allowsInput(at: 1.91))
        XCTAssertTrue(latch.accept(.previous, source: .swipe, at: 1.92))
    }

    func testBeginSwitchStartsSwitchingWithoutWaitingForRelease() {
        var latch = InputCommandLatch(cooldownInterval: 0.7)

        XCTAssertTrue(latch.beginSwitch(.next, source: .swipe, at: 1.0))
        XCTAssertEqual(latch.state, .switching)
        XCTAssertFalse(latch.accept(.previous, source: .keyboard, at: 1.1))
    }

    func testModifierReleasePolicyWaitsForEveryTriggerModifier() {
        let trigger: ModifierFlags = [.option, .shift]

        XCTAssertFalse(InputModifierReleasePolicy.didReleaseAllTriggerModifiers(
            currentModifiers: [.option, .shift],
            triggerModifiers: trigger
        ))
        XCTAssertFalse(InputModifierReleasePolicy.didReleaseAllTriggerModifiers(
            currentModifiers: [.option],
            triggerModifiers: trigger
        ))
        XCTAssertFalse(InputModifierReleasePolicy.didReleaseAllTriggerModifiers(
            currentModifiers: [.shift],
            triggerModifiers: trigger
        ))
        XCTAssertTrue(InputModifierReleasePolicy.didReleaseAllTriggerModifiers(
            currentModifiers: [],
            triggerModifiers: trigger
        ))
    }

    func testModifierStateCombinerMergesEventAndCurrentModifiers() {
        XCTAssertEqual(
            InputModifierStateCombiner.effectiveModifiers(
                eventModifiers: [.option],
                currentModifiers: [.shift]
            ),
            [.option, .shift]
        )
    }

    func testGestureModifierMatchPolicyRejectsExtraConfigurableModifiers() {
        XCTAssertTrue(InputModifierMatchPolicy.gestureModifiersMatch(
            eventModifiers: [.option, .shift],
            requiredModifiers: [.option, .shift]
        ))
        XCTAssertTrue(InputModifierMatchPolicy.gestureModifiersMatch(
            eventModifiers: [.option, .shift, .function],
            requiredModifiers: [.option, .shift]
        ))
        XCTAssertFalse(InputModifierMatchPolicy.gestureModifiersMatch(
            eventModifiers: [.control, .option, .shift],
            requiredModifiers: [.option, .shift]
        ))
    }

    func testResetClearsPendingCommand() {
        var latch = InputCommandLatch(cooldownInterval: 0.7)

        XCTAssertTrue(latch.accept(.next, source: .swipe, at: 1.0))
        latch.reset()

        XCTAssertNil(latch.releasePending(source: .swipe))
        XCTAssertTrue(latch.accept(.previous, source: .keyboard, at: 1.1))
    }
}
