import AppKit
import QuartzCore
import XCTest
@testable import SidebyApp

@MainActor final class HeldWorkspaceWheelSurroundTests: XCTestCase {
    func testCueWaitsForVisibilityAndRunsOnceWithoutChangingTheWindowOrHitArea() throws {
        let view = HeldWorkspaceWheelSurround.SurroundView(frame: NSRect(x: 0, y: 0, width: 384, height: 384))
        view.configure(geometry: .init(), count: 4, isActive: true, reduceMotion: false)
        view.layoutSubtreeIfNeeded()
        let frame = view.frame
        view.revealIfNeeded(isVisible: false)
        XCTAssertNil(view.highlight.animation(forKey: "appearance"))
        view.revealIfNeeded(isVisible: true)
        let cue = try XCTUnwrap(view.highlight.animation(forKey: "appearance") as? CAKeyframeAnimation)
        XCTAssertEqual(cue.keyPath, "opacity")
        XCTAssertEqual(cue.duration, 0.7)
        XCTAssertEqual(cue.values as? [Int], [1, 1, 0])
        XCTAssertEqual(try XCTUnwrap(cue.keyTimes?[1]).doubleValue * cue.duration, 0.4, accuracy: 0.001,
                       "The cue stays fully visible long enough to notice before fading")
        XCTAssertEqual(view.highlight.opacity, 0, "The model layer settles back to the permanent outline")
        XCTAssertEqual(view.frame, frame)
        XCTAssertNil(view.hitTest(.init(x: 192, y: 2)), "Decoration cannot intercept the wheel's controls")
        view.highlight.removeAllAnimations()
        view.revealIfNeeded(isVisible: true)
        XCTAssertNil(view.highlight.animation(forKey: "appearance"), "Hover and ordinary refresh must not replay the cue")
    }

    func testLeavingWheelCancelsCueAndReturningCanRevealOnceAgain() {
        let view = HeldWorkspaceWheelSurround.SurroundView()
        view.configure(geometry: .init(), count: 2, isActive: true, reduceMotion: false)
        view.revealIfNeeded(isVisible: true)
        XCTAssertNotNil(view.highlight.animation(forKey: "appearance"))
        view.configure(geometry: .init(), count: 2, isActive: false, reduceMotion: false)
        view.revealIfNeeded(isVisible: true)
        XCTAssertNil(view.highlight.animation(forKey: "appearance"))
        view.configure(geometry: .init(), count: 2, isActive: true, reduceMotion: false)
        view.revealIfNeeded(isVisible: true)
        XCTAssertNotNil(view.highlight.animation(forKey: "appearance"))
    }

    func testReduceMotionKeepsStaticOutlineAndCancelsAnInFlightCue() {
        let view = HeldWorkspaceWheelSurround.SurroundView(frame: NSRect(x: 0, y: 0, width: 320, height: 320))
        view.configure(geometry: .init(), count: 8, isActive: true, reduceMotion: true)
        view.layoutSubtreeIfNeeded()
        view.revealIfNeeded(isVisible: true)
        XCTAssertNil(view.highlight.animation(forKey: "appearance"))
        XCTAssertNotNil(view.highlight.path)
        view.configure(geometry: .init(), count: 8, isActive: false, reduceMotion: false)
        view.configure(geometry: .init(), count: 8, isActive: true, reduceMotion: false)
        view.revealIfNeeded(isVisible: true)
        XCTAssertNotNil(view.highlight.animation(forKey: "appearance"))
        view.configure(geometry: .init(), count: 8, isActive: true, reduceMotion: true)
        XCTAssertNil(view.highlight.animation(forKey: "appearance"))
    }
}
