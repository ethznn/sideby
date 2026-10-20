import AppKit
import SidebyCore
import SidebySystem
import SidebyUI
import SwiftUI

@MainActor
final class ProductContextHUDController {
    static let shared = ProductContextHUDController()

    typealias Animation = @MainActor (TimeInterval, @escaping @MainActor () -> Void, @escaping @MainActor () -> Void) -> Void
    private var panels: [NSPanel] = []
    private var showWorkItem: DispatchWorkItem?
    private var hideWorkItem: DispatchWorkItem?
    private var presentationGeneration = HUDPresentationGeneration()
    private var currentTiming: HUDPresentationState?
    private var displayedAt: TimeInterval?
    private var dismissalRequested = false
    private let panelFactory: @MainActor () -> NSPanel
    private let now: @MainActor () -> TimeInterval
    private let schedule: @MainActor (TimeInterval, DispatchWorkItem) -> Void
    private let animate: Animation
    private let reduceMotion: @MainActor () -> Bool

    // Inject scheduling and window ordering for deterministic tests which never
    // present a window or change the user's active Space.
    init(
        panelFactory: @escaping @MainActor () -> NSPanel = ProductContextHUDController.makePanel,
        now: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        schedule: @escaping @MainActor (TimeInterval, DispatchWorkItem) -> Void = {
            DispatchQueue.main.asyncAfter(deadline: .now() + $0, execute: $1)
        },
        animate: @escaping Animation = ProductContextHUDController.animateWindows,
        reduceMotion: @escaping @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    ) {
        self.panelFactory = panelFactory
        self.now = now
        self.schedule = schedule
        self.animate = animate
        self.reduceMotion = reduceMotion
    }

    @discardableResult
    func show(_ state: HUDPresentationState, screen: NSScreen? = NSScreen.main) -> Int {
        show(state, screens: [screen ?? NSScreen.main ?? NSScreen.screens.first].compactMap(\.self))
    }

    @discardableResult
    func show(_ state: HUDPresentationState, displayIDs: Set<String>, displayLayout: DisplayLayout) -> Int {
        let screens = screens(for: displayIDs, displayLayout: displayLayout)
        return show(screenStates: screens.map { ($0, state) }, timing: state)
    }

    func show(
        statesByDisplayID: [String: HUDPresentationState],
        displayLayout: DisplayLayout,
        timing: HUDPresentationState
    ) {
        let screenStates = displayLayout.displays.compactMap { display -> (NSScreen, HUDPresentationState)? in
            guard let state = statesByDisplayID[display.id],
                  let screen = screen(forDisplayID: display.id)
            else {
                return nil
            }
            return (screen, state)
        }
        _ = show(screenStates: screenStates, timing: timing)
    }

    private func show(_ state: HUDPresentationState, screens requestedScreens: [NSScreen]) -> Int {
        show(screenStates: requestedScreens.map { ($0, state) }, timing: state)
    }

    func show(
        screenStates requestedScreenStates: [(NSScreen, HUDPresentationState)],
        timing: HUDPresentationState
    ) -> Int {
        let generation = presentationGeneration.advance()
        showWorkItem?.cancel()
        hideWorkItem?.cancel()
        showWorkItem = nil
        hideWorkItem = nil
        currentTiming = timing
        displayedAt = nil
        dismissalRequested = false

        let screenStates = requestedScreenStates.isEmpty
            ? [NSScreen.main ?? NSScreen.screens.first].compactMap(\.self).map { ($0, timing) }
            : requestedScreenStates
        guard !screenStates.isEmpty else {
            return generation
        }

        if timing.appearanceDelay > 0, !panels.contains(where: \.isVisible) {
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.presentationGeneration.isCurrent(generation),
                          !self.dismissalRequested else { return }
                    self.present(screenStates, timing: timing, generation: generation)
                }
            }
            showWorkItem = work
            schedule(timing.appearanceDelay, work)
        } else {
            // A new target replaces an already visible HUD without hiding it.
            present(screenStates, timing: timing, generation: generation)
        }
        return generation
    }

    private func present(
        _ screenStates: [(NSScreen, HUDPresentationState)],
        timing: HUDPresentationState,
        generation: Int
    ) {
        showWorkItem = nil
        while panels.count < screenStates.count { panels.append(panelFactory()) }
        let fadeIn = reduceMotion() ? 0 : timing.fadeInDuration
        var activePanels: [NSPanel] = []
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            for (index, panel) in panels.enumerated() {
                guard index < screenStates.count else {
                    panel.orderOut(nil)
                    continue
                }
                let (screen, state) = screenStates[index]
                let wasVisible = panel.isVisible
                let hostingController: NSHostingController<HUDView>
                if let existing = panel.contentViewController as? NSHostingController<HUDView> {
                    hostingController = existing
                    if existing.rootView.state != state { existing.rootView = HUDView(state: state) }
                } else {
                    hostingController = NSHostingController(rootView: HUDView(state: state))
                    panel.contentViewController = hostingController
                }
                applyContentSize(to: panel, hostingView: hostingController.view, state: state)
                position(panel, on: screen)
                // Complete layout before ordering; do not reposition next run
                // loop when a newer HUD may already own this reused panel.
                panel.displayIfNeeded()
                if !wasVisible {
                    panel.alphaValue = fadeIn > 0 ? 0 : 1
                    panel.orderFrontRegardless()
                }
                activePanels.append(panel)
            }
        }
        displayedAt = now()
        animate(fadeIn, {
            activePanels.forEach { $0.animator().alphaValue = 1 }
        }, {})
        if timing.dismissalMode == .automatic {
            scheduleFadeOut(activePanels, state: timing, generation: generation,
                            delay: max(timing.duration, timing.minimumVisibleDuration))
        }
    }

    func dismiss(generation: Int) {
        guard presentationGeneration.isCurrent(generation), !dismissalRequested,
              let timing = currentTiming else { return }
        dismissalRequested = true
        showWorkItem?.cancel()
        showWorkItem = nil
        hideWorkItem?.cancel()
        hideWorkItem = nil
        guard let displayedAt else {
            // The operation finished before the delay. Nothing is ever shown.
            presentationGeneration.consumeCurrent(generation)
            currentTiming = nil
            return
        }
        let remaining = max(0, timing.minimumVisibleDuration - (now() - displayedAt))
        scheduleFadeOut(panels.filter(\.isVisible), state: timing, generation: generation, delay: remaining)
    }

    private func screen(forDisplayID displayID: String) -> NSScreen? {
        NSScreen.screens.first { Self.stableDisplayID(for: $0) == displayID }
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 180, height: 52)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.level = .screenSaver
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        panel.collectionBehavior.insert([
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient
        ])
        return panel
    }

    private func applyContentSize(
        to panel: NSPanel,
        hostingView: NSView,
        state: HUDPresentationState
    ) {
        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize
        let contentSize = HUDPanelLayout.contentSize(
            fittingSize: fittingSize,
            text: state.text,
            visualScale: state.visualScale
        )
        panel.setContentSize(contentSize)
    }

    private func position(_ panel: NSPanel, on screen: NSScreen?) {
        guard let screen else {
            return
        }

        let frame = panel.frame
        panel.setFrame(
            NSRect(
                origin: HUDPanelLayout.centeredOrigin(panelSize: frame.size, screenFrame: screen.frame),
                size: frame.size
            ),
            display: true
        )
    }

    private func screens(for displayIDs: Set<String>, displayLayout: DisplayLayout) -> [NSScreen] {
        let requestedDisplayIDs = displayIDs.isEmpty
            ? Set(displayLayout.displays.map(\.id))
            : displayIDs
        let screensByDisplayID = Dictionary(
            uniqueKeysWithValues: NSScreen.screens.compactMap { screen -> (String, NSScreen)? in
                guard let displayID = Self.stableDisplayID(for: screen) else {
                    return nil
                }
                return (displayID, screen)
            }
        )
        let screens = displayLayout.displays.compactMap { display -> NSScreen? in
            guard requestedDisplayIDs.contains(display.id) else {
                return nil
            }
            return screensByDisplayID[display.id]
        }

        return screens.isEmpty ? NSScreen.screens : screens
    }

    private static func stableDisplayID(for screen: NSScreen) -> String? {
        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[screenNumberKey] as? NSNumber else {
            return nil
        }

        let displayID = CGDirectDisplayID(number.uint32Value)
        return DisplayLayoutMapper.stableID(for: DisplaySnapshot(
            displayID: displayID, name: screen.localizedName,
            isPrimary: CGDisplayIsMain(displayID) != 0, isBuiltin: CGDisplayIsBuiltin(displayID) != 0,
            vendorNumber: CGDisplayVendorNumber(displayID), modelNumber: CGDisplayModelNumber(displayID),
            serialNumber: CGDisplaySerialNumber(displayID), displayUUID: DisplayLayoutMapper.displayUUID(for: displayID)
        ))
    }

    private func scheduleFadeOut(
        _ activePanels: [NSPanel],
        state: HUDPresentationState,
        generation: Int,
        delay: TimeInterval
    ) {
        let workItem = DispatchWorkItem { [weak self, activePanels] in
            MainActor.assumeIsolated {
                guard let self, self.presentationGeneration.isCurrent(generation) else { return }
                self.animate(self.reduceMotion() ? 0 : state.fadeOutDuration, {
                    activePanels.forEach { $0.animator().alphaValue = 0 }
                }, { [weak self, activePanels] in
                    guard let self, self.presentationGeneration.isCurrent(generation) else {
                        return
                    }
                    activePanels.forEach { panel in
                        panel.orderOut(nil)
                        panel.alphaValue = 1
                    }
                    self.presentationGeneration.consumeCurrent(generation)
                    self.currentTiming = nil
                    self.displayedAt = nil
                    self.hideWorkItem = nil
                })
            }
        }
        hideWorkItem = workItem
        schedule(delay, workItem)
    }

    private static func animateWindows(
        duration: TimeInterval,
        changes: @escaping @MainActor () -> Void,
        completion: @escaping @MainActor () -> Void
    ) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            changes()
        } completionHandler: {
            Task { @MainActor in completion() }
        }
    }
}
