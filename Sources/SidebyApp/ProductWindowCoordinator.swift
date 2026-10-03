import AppKit
import SwiftUI

@MainActor
final class ProductWindowCoordinator: NSObject, NSWindowDelegate {
    enum Kind: Hashable { case settings, onboarding }

    let navigation: ProductUINavigation
    var presentDaily: (() -> Void)?
    var settingsHasUnsavedChanges: () -> Bool = { false }
    var resolveSettingsChanges: ((NSWindow, @escaping @MainActor () -> Void) -> Void)?
    private let settingsContent: (ProductWindowCoordinator) -> AnyView
    private let onboardingContent: (ProductWindowCoordinator) -> AnyView
    private let closeDaily: () -> Void
    private let refreshState: () -> Void
    private let onboardingWillShow: (Bool) -> Void
    private let onboardingWillClose: () -> Void
    private let activateApplication: () -> Void
    private var controllers: [Kind: NSWindowController] = [:]

    init(navigation: ProductUINavigation,
         settingsContent: @escaping (ProductWindowCoordinator) -> AnyView,
         onboardingContent: @escaping (ProductWindowCoordinator) -> AnyView,
         closeDaily: @escaping () -> Void, refreshState: @escaping () -> Void,
         onboardingWillShow: @escaping (Bool) -> Void,
         onboardingWillClose: @escaping () -> Void,
         activateApplication: @escaping () -> Void = { NSApp.activate(ignoringOtherApps: true) }) {
        self.navigation = navigation
        self.settingsContent = settingsContent
        self.onboardingContent = onboardingContent
        self.closeDaily = closeDaily
        self.refreshState = refreshState
        self.onboardingWillShow = onboardingWillShow
        self.onboardingWillClose = onboardingWillClose
        self.activateApplication = activateApplication
    }

    func makeWindow(for kind: Kind) -> NSWindow {
        if let window = controllers[kind]?.window { return window }
        let size = kind == .settings ? NSSize(width: 980, height: 720) : NSSize(width: 640, height: 520)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.collectionBehavior = kind == .settings
            ? [.moveToActiveSpace, .fullScreenAuxiliary]
            : [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.title = "Sideby"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentMinSize = kind == .settings ? NSSize(width: 700, height: 560) : NSSize(width: 560, height: 420)
        controllers[kind] = NSWindowController(window: window)
        window.contentViewController = NSHostingController(rootView: kind == .settings ? settingsContent(self) : onboardingContent(self))
        // Hosting can resize to SwiftUI's minimum fitting size when attached.
        // Apply the intended initial size after attachment, once per window.
        window.setContentSize(size)
        window.center()
        if let screen = window.screen ?? NSScreen.main {
            var frame = window.frame
            frame.size.width = min(frame.width, screen.visibleFrame.width)
            frame.size.height = min(frame.height, screen.visibleFrame.height)
            window.setFrame(window.constrainFrameRect(frame, to: screen), display: false)
        }
        return window
    }

    func showSettings(_ route: ProductSettingsRoute? = nil) {
        navigation.openSettings(route)
        present(makeWindow(for: .settings))
    }

    func showOnboarding(replay: Bool = false) {
        present(makeWindow(for: .onboarding)) {
            onboardingWillShow(replay)
        }
    }

    func closeOnboarding() {
        controllers[.onboarding]?.window?.close()
    }

    func returnAfterAssignmentReview() {
        if settingsHasUnsavedChanges(), let window = controllers[.settings]?.window, let resolveSettingsChanges {
            resolveSettingsChanges(window) { [weak self] in self?.returnAfterAssignmentReview() }; return
        }
        guard let destination = navigation.consumeReturnDestination() else { return }
        controllers[.settings]?.window?.orderOut(nil)
        switch destination {
        case .daily: presentDaily?()
        case .onboarding: showOnboarding()
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        refreshState()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === controllers[.settings]?.window, settingsHasUnsavedChanges(), let resolveSettingsChanges {
            resolveSettingsChanges(sender) { [weak sender] in sender?.close() }; return false
        }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === controllers[.onboarding]?.window {
            onboardingWillClose()
        } else if window === controllers[.settings]?.window {
            if navigation.consumeReturnDestination() == .onboarding { showOnboarding() }
        }
    }

    private func present(_ window: NSWindow, willPresent: () -> Void = {}) {
        closeDaily()
        refreshState()
        willPresent()
        activateApplication()
        window.makeKeyAndOrderFront(nil)
        // Activation is asynchronous for this menu-bar app. Honor the explicit
        // open request even while another application still owns the key window.
        window.orderFrontRegardless()
    }
}
