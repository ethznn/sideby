import AppKit
import SidebyCore
import SidebyUI
import SwiftUI
import XCTest
@testable import SidebyApp

// Ordering is intercepted, so these tests neither display windows nor send
// input. The production controller and its hosting views still run unchanged.
@MainActor final class ProductContextHUDTests: XCTestCase {
    private final class Panel: NSPanel {
        var shown = false
        var orderIns = 0
        var orderOuts = 0
        var alphaAtOrder: CGFloat?
        override var isVisible: Bool { shown }
        var actuallyVisible: Bool { super.isVisible }
        override func orderFrontRegardless() {
            alphaAtOrder = alphaValue
            orderIns += 1
            shown = true
        }
        override func orderOut(_ sender: Any?) {
            orderOuts += 1
            shown = false
        }
    }

    @MainActor private final class Harness {
        var time: TimeInterval = 0
        var jobs: [(TimeInterval, DispatchWorkItem)] = []
        var panels: [Panel] = []
        var animations: [TimeInterval] = []
        var completions: [@MainActor () -> Void] = []
        var reducesMotion = false
        lazy var controller = ProductContextHUDController(
            panelFactory: { [unowned self] in
                let panel = Panel(contentRect: NSRect(x: 0, y: 0, width: 180, height: 52),
                    styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.isReleasedWhenClosed = false
                panels.append(panel)
                return panel
            },
            now: { [unowned self] in time },
            schedule: { [unowned self] delay, work in jobs.append((time + delay, work)) },
            animate: { [unowned self] duration, changes, completion in
                animations.append(duration)
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0
                    changes()
                }
                completions.append(completion)
            },
            reduceMotion: { [unowned self] in reducesMotion }
        )

        func advance(to target: TimeInterval) {
            while let index = jobs.indices.filter({ jobs[$0].0 <= target })
                .min(by: { jobs[$0].0 < jobs[$1].0 }) {
                let (deadline, job) = jobs.remove(at: index)
                time = deadline
                if !job.isCancelled { job.perform() }
            }
            time = target
        }

        func completeAnimations() {
            let pending = completions
            completions.removeAll()
            pending.forEach { $0() }
        }

        func close() {
            jobs.forEach { $0.1.cancel() }
            panels.forEach {
                XCTAssertFalse($0.actuallyVisible, "Tests must never order real windows onto the desktop")
                $0.close()
            }
        }
    }

    func testFastTransitionNeverCreatesOrShowsHUD() throws {
        let harness = Harness()
        defer { harness.close() }
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let state = HUDPresenter().stateForContextTransition(contextName: "Checkout")
        let generation = harness.controller.show(state, screen: screen)
        harness.advance(to: 0.08)
        harness.controller.dismiss(generation: generation)
        harness.advance(to: 2)
        XCTAssertTrue(harness.panels.isEmpty)
        XCTAssertTrue(harness.animations.isEmpty)
    }

    func testLongerTransitionFadesOnlyAfterMinimumVisibility() throws {
        let harness = Harness()
        defer { harness.close() }
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let state = HUDPresenter().stateForContextTransition(contextName: "Checkout")
        let generation = harness.controller.show(state, screen: screen)
        harness.advance(to: 0.149)
        XCTAssertTrue(harness.panels.isEmpty)
        harness.advance(to: 0.15)
        let panel = try XCTUnwrap(harness.panels.first)
        XCTAssertEqual(panel.alphaAtOrder, 0)
        XCTAssertEqual(harness.animations, [0.12])
        XCTAssertEqual(panel.frame.midX, screen.frame.midX, accuracy: 0.5)
        XCTAssertEqual(panel.frame.midY, screen.frame.midY, accuracy: 0.5)
        harness.completeAnimations()
        harness.advance(to: 0.16)
        harness.controller.dismiss(generation: generation)
        harness.controller.dismiss(generation: generation)
        harness.advance(to: 0.349)
        XCTAssertTrue(panel.shown)
        XCTAssertEqual(harness.animations.count, 1)
        harness.advance(to: 0.351)
        XCTAssertEqual(harness.animations, [0.12, 0.16])
        XCTAssertTrue(panel.shown, "Do not abruptly remove a fading HUD")
        harness.completeAnimations()
        XCTAssertFalse(panel.shown)
        XCTAssertEqual(panel.orderOuts, 1)
    }

    func testNewTargetReusesVisibleHostAndRejectsOldFadeCompletion() throws {
        let harness = Harness()
        defer { harness.close() }
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let first = harness.controller.show(HUDPresenter().stateForContextTransition(contextName: "Checkout"), screen: screen)
        harness.advance(to: 0.15)
        harness.completeAnimations()
        let panel = try XCTUnwrap(harness.panels.first)
        let host = try XCTUnwrap(panel.contentViewController)
        harness.advance(to: 0.4)
        harness.controller.dismiss(generation: first)
        harness.advance(to: 0.4) // The old fade starts, but has not finished.
        let second = harness.controller.show(HUDPresenter().stateForContextTransition(contextName: "PR review"), screen: screen)
        XCTAssertTrue(panel.contentViewController === host)
        XCTAssertEqual(panel.orderIns, 1, "Updating a visible HUD must not hide and re-order it")
        XCTAssertEqual(panel.orderOuts, 0)
        XCTAssertEqual((host as? NSHostingController<HUDView>)?.rootView.state.text, "PR review")
        harness.controller.dismiss(generation: first)
        harness.completeAnimations()
        XCTAssertTrue(panel.shown, "A stale completion must not hide the new target")
        XCTAssertEqual(panel.orderOuts, 0)
        harness.controller.dismiss(generation: second)
        harness.advance(to: 1)
        harness.completeAnimations()
        XCTAssertFalse(panel.shown)
    }

    func testSupersededPendingTargetCannotAppearLater() throws {
        let harness = Harness()
        defer { harness.close() }
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let first = harness.controller.show(HUDPresenter().stateForContextTransition(contextName: "Old"), screen: screen)
        harness.advance(to: 0.1)
        let second = harness.controller.show(HUDPresenter().stateForContextTransition(contextName: "New"), screen: screen)
        harness.controller.dismiss(generation: first)
        harness.advance(to: 0.2)
        XCTAssertTrue(harness.panels.isEmpty)
        harness.controller.dismiss(generation: second)
        harness.advance(to: 1)
        XCTAssertTrue(harness.panels.isEmpty)
    }

    func testMultipleDisplaysAndAutomaticFeedbackKeepExistingBehavior() throws {
        let harness = Harness()
        defer { harness.close() }
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let state = HUDPresentationState(text: "Aligned", duration: 0.8, fadeOutDuration: 0.24)
        _ = harness.controller.show(screenStates: [(screen, state), (screen, state)], timing: state)
        XCTAssertEqual(harness.panels.count, 2)
        XCTAssertTrue(harness.panels.allSatisfy(\.shown))
        harness.completeAnimations()
        let host = harness.panels[0].contentViewController
        harness.advance(to: 0.2)
        _ = harness.controller.show(HUDPresentationState(text: "Sideby off"), screen: screen)
        XCTAssertTrue(harness.panels[0].contentViewController === host)
        XCTAssertEqual(harness.panels[0].orderIns, 1)
        XCTAssertFalse(harness.panels[1].shown)
        harness.advance(to: 0.81)
        harness.completeAnimations()
        XCTAssertTrue(harness.panels[0].shown, "Old automatic timeout must not hide newer feedback")
        harness.advance(to: 1.01)
        harness.completeAnimations()
        XCTAssertFalse(harness.panels[0].shown)
    }

    func testReducedMotionStillSkipsFastHUDAndDisablesFades() throws {
        let harness = Harness()
        harness.reducesMotion = true
        defer { harness.close() }
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let state = HUDPresenter().stateForContextTransition(contextName: "Checkout")
        let generation = harness.controller.show(state, screen: screen)
        harness.advance(to: 0.15)
        XCTAssertEqual(harness.panels.first?.alphaAtOrder, 1)
        harness.controller.dismiss(generation: generation)
        harness.advance(to: 1)
        harness.completeAnimations()
        XCTAssertTrue(harness.animations.allSatisfy { $0 == 0 })
        XCTAssertFalse(try XCTUnwrap(harness.panels.first).shown)
    }
}

@MainActor final class HeldMatrixPanelRefreshTests: XCTestCase {
    private final class OrderingProbe: HeldMatrixPanel {
        var shown = true
        var operations: [String] = []
        var contexts: [(TimeInterval, Bool)] = []
        override var isVisible: Bool { shown }
        var actuallyVisible: Bool { super.isVisible }
        override func orderOut(_ sender: Any?) {
            operations.append("out"); shown = false
            contexts.append((NSAnimationContext.current.duration, NSAnimationContext.current.allowsImplicitAnimation))
        }
        override func orderFrontRegardless() {
            operations.append("front"); shown = true
            contexts.append((NSAnimationContext.current.duration, NSAnimationContext.current.allowsImplicitAnimation))
        }
    }

    func testRefreshKeepsInputRecoveryInSingleNonanimatedGroupAndNeverResurrectsDismissedPanel() {
        let panel = OrderingProbe(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        defer { panel.close() }
        var session = HeldMatrixSession()
        session.press()
        XCTAssertTrue(panel.refreshOrderIfVisible(session: session, chordIsDown: true))
        XCTAssertEqual(panel.operations, ["out", "front"])
        XCTAssertTrue(panel.contexts.allSatisfy { $0.0 == 0 && !$0.1 })
        XCTAssertFalse(panel.actuallyVisible)
        panel.operations.removeAll()
        XCTAssertFalse(panel.refreshOrderIfVisible(session: session, chordIsDown: false))
        session.release()
        XCTAssertFalse(panel.refreshOrderIfVisible(session: session, chordIsDown: true))
        session.press()
        panel.shown = false
        XCTAssertFalse(panel.refreshOrderIfVisible(session: session, chordIsDown: true))
        XCTAssertTrue(panel.operations.isEmpty)
    }
}
