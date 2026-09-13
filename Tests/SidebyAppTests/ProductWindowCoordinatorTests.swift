import AppKit
import SwiftUI
import XCTest
@testable import SidebyApp

@MainActor
final class ProductWindowCoordinatorTests: XCTestCase {
    func testSettingsOpensInFrontWhileAccessoryApplicationActivationIsPending() async throws {
        guard ProcessInfo.processInfo.environment["SIDEBY_NATIVE_WINDOW_FOCUS"] == "1" else {
            throw XCTSkip("Opt-in foreground window verification in a graphical macOS session")
        }
        let application = NSApplication.shared
        let previousPolicy = application.activationPolicy()
        let previousApplication = NSWorkspace.shared.frontmostApplication
        guard previousApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            throw XCTSkip("This regression requires another application to be active initially")
        }
        application.setActivationPolicy(.accessory)
        let coordinator = ProductWindowCoordinator(
            navigation: ProductUINavigation(preferences: MemoryProductUIPreferences()),
            settingsContent: { _ in AnyView(Text("Sideby window focus verification")) },
            onboardingContent: { _ in AnyView(EmptyView()) },
            closeDaily: {}, refreshState: {}, onboardingWillShow: { _ in }, onboardingWillClose: {},
            // AppKit may defer activation. Keep another app active while exercising
            // the real NSWindow ordering, rather than assuming a request succeeded.
            activateApplication: {})
        let window = coordinator.makeWindow(for: .settings)
        defer {
            window.close()
            application.setActivationPolicy(previousPolicy)
            previousApplication?.activate(options: [])
        }
        XCTAssertFalse(application.isActive)
        coordinator.showSettings()
        // The Window Server commits an ordering request after the current run-loop turn.
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(window.level, .normal, "Settings should come forward on request, without staying above other apps")
        let windows = try XCTUnwrap(CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]])
        let foremostNormalWindow = windows.first { info in
            (info[kCGWindowLayer as String] as? Int) == 0
                && (info[kCGWindowAlpha as String] as? Double ?? 0) > 0
        }
        XCTAssertEqual(foremostNormalWindow?[kCGWindowNumber as String] as? Int, window.windowNumber,
                       "Opening Settings must bring it in front even before app activation completes")
    }

    func testConstructionRetainsOneWindowPerKindWithoutPresentationSideEffects() {
        let preferences = MemoryProductUIPreferences()
        let navigation = ProductUINavigation(preferences: preferences)
        var effects = 0
        var settingsFactories = 0
        let coordinator = ProductWindowCoordinator(
            navigation: navigation,
            settingsContent: { _ in settingsFactories += 1; return AnyView(Text("Settings")) },
            onboardingContent: { _ in AnyView(Text("Guide")) },
            closeDaily: { effects += 1 }, refreshState: { effects += 1 },
            onboardingWillShow: { _ in effects += 1 }, onboardingWillClose: { effects += 1 }
        )
        let first = coordinator.makeWindow(for: .settings)
        XCTAssertTrue(first === coordinator.makeWindow(for: .settings))
        XCTAssertFalse(first === coordinator.makeWindow(for: .onboarding))
        let guide = coordinator.makeWindow(for: .onboarding)
        XCTAssertTrue(first.collectionBehavior.contains(.moveToActiveSpace))
        XCTAssertFalse(first.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(guide.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertFalse(guide.collectionBehavior.contains(.moveToActiveSpace))
        for window in [first, guide] {
            XCTAssertTrue(window.collectionBehavior.contains(.fullScreenAuxiliary))
            XCTAssertEqual(window.level, .normal)
            XCTAssertFalse(window.isVisible)
        }
        // A small SwiftUI fitting size must not shrink the initial settings table/guide.
        for (window, expected) in [(first, NSSize(width: 840, height: 620)), (guide, NSSize(width: 640, height: 520))] {
            let screenSize = window.screen?.visibleFrame.size ?? expected
            let chrome = window.frame.height - window.contentRect(forFrameRect: window.frame).height
            let content = window.contentRect(forFrameRect: window.frame).size
            XCTAssertEqual(content.width, min(expected.width, screenSize.width), accuracy: 1)
            XCTAssertEqual(content.height, min(expected.height, screenSize.height - chrome), accuracy: 1)
        }
        XCTAssertEqual(settingsFactories, 1)
        XCTAssertEqual(effects, 0)
        XCTAssertFalse(first.isVisible)
        XCTAssertFalse(first.isReleasedWhenClosed)
    }

    func testClosingSettingsDiscardsDailyIntentWithoutMutatingPreferencesOrShowingAnything() {
        let preferences = MemoryProductUIPreferences()
        preferences.didCompletePermissionSetup = true
        let navigation = ProductUINavigation(preferences: preferences)
        navigation.openSettings(.init(pane: .workspaces, contextID: "a", returnTo: .daily))
        var effects = 0
        let coordinator = ProductWindowCoordinator(
            navigation: navigation,
            settingsContent: { _ in AnyView(EmptyView()) }, onboardingContent: { _ in AnyView(EmptyView()) },
            closeDaily: { effects += 1 }, refreshState: { effects += 1 },
            onboardingWillShow: { _ in effects += 1 }, onboardingWillClose: { effects += 1 }
        )
        coordinator.presentDaily = { effects += 1 }
        coordinator.makeWindow(for: .settings).close()
        XCTAssertNil(navigation.consumeReturnDestination())
        XCTAssertTrue(preferences.didCompletePermissionSetup)
        XCTAssertEqual(preferences.lastSettingsPane, .workspaces)
        XCTAssertEqual(effects, 0)
    }

    func testClosingOnboardingCallsOnlyItsCloseHook() {
        let preferences = MemoryProductUIPreferences()
        preferences.onboardingStage = .roundTrip
        var didClose = 0
        let coordinator = ProductWindowCoordinator(
            navigation: ProductUINavigation(preferences: preferences),
            settingsContent: { _ in AnyView(EmptyView()) }, onboardingContent: { _ in AnyView(EmptyView()) },
            closeDaily: {}, refreshState: {}, onboardingWillShow: { _ in },
            onboardingWillClose: { didClose += 1 }
        )
        coordinator.makeWindow(for: .onboarding).close()
        XCTAssertEqual(didClose, 1)
        XCTAssertEqual(preferences.onboardingStage, .roundTrip)
    }

    func testSuccessfulDailyReviewConsumesReturnOnceWithoutPresentingAnotherNativeWindow() {
        let navigation = ProductUINavigation(preferences: MemoryProductUIPreferences())
        navigation.openSettings(.init(pane: .workspaces, contextID: "review", returnTo: .daily))
        var dailyOpens = 0
        var otherEffects = 0
        let coordinator = ProductWindowCoordinator(
            navigation: navigation,
            settingsContent: { _ in AnyView(EmptyView()) }, onboardingContent: { _ in AnyView(EmptyView()) },
            closeDaily: { otherEffects += 1 }, refreshState: { otherEffects += 1 },
            onboardingWillShow: { _ in otherEffects += 1 }, onboardingWillClose: { otherEffects += 1 }
        )
        coordinator.presentDaily = { dailyOpens += 1 }
        _ = coordinator.makeWindow(for: .settings)
        coordinator.returnAfterAssignmentReview()
        coordinator.returnAfterAssignmentReview()
        XCTAssertEqual(dailyOpens, 1)
        XCTAssertEqual(otherEffects, 0)
        XCTAssertEqual(navigation.settingsRoute.contextID, "review")
        XCTAssertNil(navigation.settingsRoute.returnTo)
    }
}
