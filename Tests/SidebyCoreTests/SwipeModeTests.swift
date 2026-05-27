import XCTest
@testable import SidebyCore

final class SwipeModeTests: XCTestCase {
    func testSwipeInputPipelineReturnsCommandAndSuppressesRepeat() {
        var pipeline = SwipeInputPipeline(settings: .default, lockoutInterval: 0.6)
        let first = InputEventFactory.horizontalSwipe(deltaX: 120, modifiers: AppSettings.defaultGestureModifiers, timestamp: 1)
        let second = InputEventFactory.horizontalSwipe(deltaX: 120, modifiers: AppSettings.defaultGestureModifiers, timestamp: 1.2)

        XCTAssertEqual(pipeline.command(for: first), .previous)
        XCTAssertNil(pipeline.command(for: second))
    }

    func testSwipeInputPipelineAccumulatesTrackpadScrollDeltas() {
        var pipeline = SwipeInputPipeline(settings: .default, lockoutInterval: 0.6, accumulationWindow: 0.35)
        let first = InputEventFactory.horizontalSwipe(deltaX: 30, modifiers: AppSettings.defaultGestureModifiers, timestamp: 1.00)
        let second = InputEventFactory.horizontalSwipe(deltaX: 30, modifiers: AppSettings.defaultGestureModifiers, timestamp: 1.08)
        let third = InputEventFactory.horizontalSwipe(deltaX: 30, modifiers: AppSettings.defaultGestureModifiers, timestamp: 1.16)

        XCTAssertNil(pipeline.command(for: first))
        XCTAssertNil(pipeline.command(for: second))
        XCTAssertEqual(pipeline.command(for: third), .previous)
    }

    func testSwipeInputPipelineResetsAccumulationAfterIdleGap() {
        var pipeline = SwipeInputPipeline(settings: .default, lockoutInterval: 0.6, accumulationWindow: 0.35)
        let first = InputEventFactory.horizontalSwipe(deltaX: 50, modifiers: AppSettings.defaultGestureModifiers, timestamp: 1.00)
        let second = InputEventFactory.horizontalSwipe(deltaX: 50, modifiers: AppSettings.defaultGestureModifiers, timestamp: 1.60)

        XCTAssertNil(pipeline.command(for: first))
        XCTAssertNil(pipeline.command(for: second))
    }

    func testDeviceProfilesExposeGestureSettings() {
        let settings = InputDeviceProfile.magicMouse.gestureSettings

        XCTAssertEqual(settings.requiredModifiers, [.option, .shift])
        XCTAssertEqual(settings.horizontalThreshold, 70)
        XCTAssertTrue(settings.ignoresMomentum)
    }

    func testAppExceptionPolicyDisablesSwipeByBundleIdentifier() {
        let policy = AppExceptionPolicy(
            exceptionList: AppExceptionList(disabledBundleIdentifiers: ["com.figma.Desktop"])
        )
        let app = ActiveAppInfo(bundleIdentifier: "com.figma.Desktop", localizedName: "Figma")

        XCTAssertFalse(policy.allowsSwipe(in: app))
        XCTAssertTrue(policy.allowsSwipe(in: ActiveAppInfo(bundleIdentifier: "com.apple.Safari", localizedName: "Safari")))
    }
}
