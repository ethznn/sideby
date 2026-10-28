import AppKit
import Combine
import SidebyCore
import SidebySystem
import SwiftUI
import XCTest
@testable import SidebyApp

@MainActor final class SwitcherOptimizationTests: XCTestCase {
    func testRepeatedWheelConstructionTimingOffscreen() async throws {
        guard ProcessInfo.processInfo.environment["SIDEBY_MEASURE_SWITCHER"] == "1" else {
            throw XCTSkip("Opt-in local switcher timing probe")
        }
        let model = heldMatrixFixture(count: 8, displayCount: 2)
        model.workspacePreferences = nil
        var milliseconds: [Double] = []
        for _ in 0..<12 {
            let started = ProcessInfo.processInfo.systemUptime
            let window = hiddenWindow(HeldWorkspaceMatrixView(model: model, snapshot: .init(model: model),
                select: { _ in XCTFail("Timing must never switch Spaces") }, usesRadial: true,
                animateEntrance: false, wheelDiameter: 440))
            milliseconds.append((ProcessInfo.processInfo.systemUptime - started) * 1000)
            XCTAssertFalse(window.isVisible)
            window.close()
            try await Task.sleep(for: .milliseconds(20))
        }
        let warm = milliseconds.dropFirst().sorted()
        print("SWITCHER_TIMING fresh_host_ms first=\(milliseconds[0]) median=\(warm[warm.count / 2]) max=\(warm.last!)")
    }

    func testHeldInputGateDoesNotRedrawProductViews() {
        let model = heldMatrixFixture(count: 8, displayCount: 2)
        var changes = 0
        let subscription = model.objectWillChange.sink { changes += 1 }
        defer { subscription.cancel() }
        for _ in 0..<10 {
            model.setHeldMatrixInputActive(true)
            XCTAssertTrue(model.heldMatrixInputActive)
            model.setHeldMatrixInputActive(false)
            XCTAssertFalse(model.heldMatrixInputActive)
        }
        XCTAssertEqual(changes, 0, "A routing-only input gate must not redraw or relayout the switcher")
    }

    func testShortcutWheelDrawsWithoutWaitingForAnEntranceAnimationOffscreen() throws {
        try requireOffscreen()
        let model = heldMatrixFixture(count: 8, displayCount: 2)
        model.workspacePreferences = nil
        let window = hiddenWindow(HeldWorkspaceMatrixView(model: model, snapshot: .init(model: model),
            select: { _ in XCTFail("Rendering must never switch Spaces") }, usesRadial: true,
            animateEntrance: false, wheelDiameter: 440))
        defer { window.close() }
        let host = try XCTUnwrap(window.contentView)
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        // No sleep/yield to finish a spring. The native cursor surface has the
        // ring's exact transformed frame, so sample the opaque center from it.
        func surface(_ view: NSView) -> WheelInteractionSurface.CursorView? {
            if let value = view as? WheelInteractionSurface.CursorView { return value }
            return view.subviews.lazy.compactMap(surface).first
        }
        let input = try XCTUnwrap(surface(host))
        let center = input.convert(CGPoint(x: input.bounds.midX, y: input.bounds.midY), to: host)
        let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
        let y = host.isFlipped ? center.y : host.bounds.height - center.y
        XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: Int(center.x * scale), y: Int(y * scale))).alphaComponent, 0.9)
        XCTAssertFalse(window.isVisible)
    }

    func testUnchangedObservationPublishesNothingAndCurrentConnectionNeverTemporarilyClears() {
        let model = heldMatrixFixture(count: 4, displayCount: 2)
        model.refreshWorkspaceStatus()
        var changes = 0
        var current: [String?] = []
        let changed = model.objectWillChange.sink { changes += 1 }
        let selection = model.$verifiedCurrentWorkspaceID.dropFirst().sink { current.append($0) }
        defer { changed.cancel(); selection.cancel() }
        for _ in 0..<10 { model.refreshWorkspaceStatus() }
        XCTAssertEqual(changes, 0)
        XCTAssertTrue(current.isEmpty)
        let old = model.workspaceLatestObservation!
        let next = WorkspaceLayoutObservation(displays: old.displays.map {
            .init(displayID: $0.displayID, spaceCount: $0.spaceCount, currentSpaceIndex: 2)
        }, spaceIDsByDisplayID: old.spaceIDsByDisplayID, spaceKeysByDisplayID: old.spaceKeysByDisplayID)
        model.workspaceObservationOverride = { next }
        model.refreshWorkspaceStatus()
        XCTAssertEqual(current, ["work-2"], "Publish the final selection, without an intermediate nil")
    }

    func testAliasUniquenessTracksDuplicateReplacementAndRemovedDisplays() throws {
        let model = heldMatrixFixture(count: 3)
        let keys = try XCTUnwrap(model.workspaceLastObservedSpaceKeys["mac"])
        let identity = try XCTUnwrap(model.desktopAliasIdentity(displayID: "mac", spaceIndex: 0))
        model.workspaceDesktopAliases[identity.storageKey] = "My work"
        XCTAssertEqual(model.desktopAlias(displayID: "mac", spaceIndex: 0), "My work")
        model.workspaceLastObservedSpaceKeys["mac"] = [keys[0], keys[0], keys[2]]
        XCTAssertNil(model.desktopAliasIdentity(displayID: "mac", spaceIndex: 0))
        model.workspaceLastObservedSpaceKeys["mac"] = keys
        XCTAssertEqual(model.desktopAlias(displayID: "mac", spaceIndex: 0), "My work")
        model.workspaceLastObservedSpaceKeys.removeValue(forKey: "mac")
        XCTAssertNil(model.desktopAliasIdentity(displayID: "mac", spaceIndex: 0))
        model.workspaceLastObservedSpaceKeys["mac"] = [keys[1], keys[0], keys[2]]
        XCTAssertEqual(model.desktopAlias(displayID: "mac", spaceIndex: 1), "My work")
    }

    func testBackgroundTitlesCoalesceAndCancelledResultsCanRetryImmediately() async throws {
        let model = heldMatrixFixture(count: 2)
        let previous = model.workspaceDesktopNames
        let provider = BlockingSwitcherTitles()
        model.workspaceNameSuggestionProvider = provider
        let first = Task { await model.refreshVisibleConnections() }
        defer { provider.resume.signal() }
        try await waitUntil { provider.readCount == 1 }
        XCTAssertFalse(provider.calledOnMain)
        _ = await model.refreshVisibleConnections(force: true)
        XCTAssertEqual(provider.readCount, 1)
        first.cancel(); provider.resume.signal()
        _ = await first.value
        XCTAssertEqual(model.workspaceDesktopNames, previous)
        XCTAssertFalse(model.connectionContentRefreshInFlight)
        provider.resume.signal()
        _ = await model.refreshVisibleConnections()
        XCTAssertEqual(provider.readCount, 2)
        XCTAssertEqual(model.workspaceDesktopNames["mac"]?[0], "Refreshed title")
    }

    func testChangedDurableIdentityDiscardsBackgroundTitlesEvenIfRuntimeIDsMatch() async throws {
        let model = heldMatrixFixture(count: 2)
        let previous = model.workspaceDesktopNames
        let provider = BlockingSwitcherTitles()
        model.workspaceNameSuggestionProvider = provider
        let task = Task { await model.refreshVisibleConnections() }
        defer { provider.resume.signal() }
        try await waitUntil { provider.readCount == 1 }
        var next = try XCTUnwrap(model.workspaceLatestObservation)
        next.spaceKeysByDisplayID["mac"] = ["replacement", "another"]
        let changed = next
        model.workspaceObservationOverride = { changed }
        provider.resume.signal(); _ = await task.value
        XCTAssertEqual(model.workspaceDesktopNames, previous)
    }

    func testToggleRespondsWhileTitleProviderIsBlockedAndActiveModeDoesNothingOffscreen() async throws {
        try requireOffscreen()
        let model = heldMatrixFixture(count: 8, displayCount: 3)
        let before = model.settings
        let provider = BlockingSwitcherTitles()
        model.workspaceNameSuggestionProvider = provider
        var changes: [HeldSwitcherPresentation] = [], pins = 0
        let window = hiddenWindow(HeldWorkspaceMatrixView(model: model, snapshot: .init(model: model),
            select: { _ in XCTFail("View changes must not switch Spaces") }, keepOpen: { pins += 1 },
            usesRadial: true, wheelDiameter: 440, presentationChanged: { changes.append($0) }))
        defer { provider.resume.signal(); window.close() }
        try await waitUntil { provider.readCount == 1 }
        try press("held-show-wheel", in: window)
        XCTAssertTrue(changes.isEmpty); XCTAssertEqual(pins, 0)
        try press("wheel-show-table", in: window)
        try await waitUntil { self.element("held-switch-table", in: window) != nil }
        try press("held-show-wheel", in: window)
        try await waitUntil { self.element("held-workspace-wheel", in: window) != nil }
        XCTAssertFalse(provider.hasReturned, "The switcher responds before another application's titles are available")
        XCTAssertFalse(provider.calledOnMain); XCTAssertEqual(provider.readCount, 1)
        XCTAssertEqual(changes, [.table, .wheel]); XCTAssertEqual(pins, 0, "View changes must preserve close-on-release")
        XCTAssertEqual(model.settings, before); XCTAssertFalse(model.isSwitching)
        XCTAssertFalse(window.isVisible); XCTAssertFalse(window.isKeyWindow)
    }

    func testRepeatedViewChangesKeepHeldLifetimeInEitherStartingModeOffscreen() async throws {
        try requireOffscreen()
        for startsWithWheel in [true, false] {
            let model = heldMatrixFixture(count: 3, displayCount: 2)
            model.workspacePreferences = nil
            var pins = 0
            let window = hiddenWindow(HeldWorkspaceMatrixView(model: model, snapshot: .init(model: model),
                select: { _ in XCTFail("Changing presentation never switches Spaces") }, keepOpen: { pins += 1 },
                usesRadial: startsWithWheel, animateEntrance: false, wheelDiameter: 440))
            defer { window.close() }
            try await waitUntil { self.element("held-view-control", in: window) != nil }
            for _ in 0..<3 {
                try press("wheel-show-table", in: window)
                try await waitUntil { self.element("held-switch-table", in: window) != nil }
                let footer = try XCTUnwrap(element("held-footer", in: window))
                let label = (footer.perform(NSSelectorFromString("accessibilityLabel"))?.takeUnretainedValue() as? String)
                    ?? (footer.perform(NSSelectorFromString("accessibilityValue"))?.takeUnretainedValue() as? String) ?? ""
                XCTAssertEqual(label, HeldMatrixStrings(language: model.settings.language).releaseHint)
                try press("held-show-wheel", in: window)
                try await waitUntil { self.element("held-workspace-wheel", in: window) != nil }
                XCTAssertEqual(pins, 0, "Neither direction may pin a shortcut-held panel")
            }
            // Genuine editing still requests a pinned panel so releasing the
            // shortcut does not abandon an editor or its confirmation.
            try press("held-edit-connections", in: window)
            try await waitUntil { self.element("current-connections-table", in: window) != nil }
            XCTAssertGreaterThan(pins, 0)
            XCTAssertFalse(window.isVisible)
        }
    }

    func testLazyTableRevealsDistantCurrentColumnAndFollowsChangedSelectionOffscreen() async throws {
        try requireOffscreen()
        let model = heldMatrixFixture(count: 24, displayCount: 3)
        let old = try XCTUnwrap(model.workspaceLatestObservation)
        func observe(_ index: Int) {
            let next = WorkspaceLayoutObservation(displays: old.displays.map {
                .init(displayID: $0.displayID, spaceCount: $0.spaceCount, currentSpaceIndex: index)
            }, spaceIDsByDisplayID: old.spaceIDsByDisplayID, spaceKeysByDisplayID: old.spaceKeysByDisplayID)
            model.workspaceObservationOverride = { next }; model.refreshWorkspaceStatus()
        }
        observe(23)
        var selected: String?
        let window = hiddenWindow(HeldWorkspaceMatrixView(model: model, snapshot: .init(model: model), select: { selected = $0.id }))
        defer { window.close() }
        try await waitUntil { self.visible("held-title-work-23", in: window) }
        try press("held-title-work-23", in: window)
        XCTAssertEqual(selected, "work-23")
        observe(0)
        try await waitUntil { self.visible("held-title-work-0", in: window) }
        try press("held-title-work-0", in: window)
        XCTAssertEqual(selected, "work-0")
        XCTAssertFalse(model.isSwitching); XCTAssertFalse(window.isVisible)
    }

    func testReturningToRetainedWheelRevealsCurrentPageAndBusyStateDisablesActionsOffscreen() async throws {
        try requireOffscreen()
        let model = heldMatrixFixture(count: 24, displayCount: 2)
        var selected = 0
        let window = hiddenWindow(HeldWorkspaceMatrixView(model: model, snapshot: .init(model: model),
            select: { _ in selected += 1 }, usesRadial: true, wheelDiameter: 440))
        defer { window.close() }
        try await waitUntil { self.element("wheel-go-work-0", in: window) != nil }
        try press("wheel-show-table", in: window)
        try await waitUntil { self.element("held-switch-table", in: window) != nil }
        let old = try XCTUnwrap(model.workspaceLatestObservation)
        let next = WorkspaceLayoutObservation(displays: old.displays.map {
            .init(displayID: $0.displayID, spaceCount: $0.spaceCount, currentSpaceIndex: 23)
        }, spaceIDsByDisplayID: old.spaceIDsByDisplayID, spaceKeysByDisplayID: old.spaceKeysByDisplayID)
        model.workspaceObservationOverride = { next }; model.refreshWorkspaceStatus()
        try press("held-show-wheel", in: window)
        try await waitUntil { self.element("wheel-go-work-23", in: window) != nil }
        model.isSwitching = true
        try await Task.sleep(for: .milliseconds(100))
        func surface(_ view: NSView) -> WheelInteractionSurface.CursorView? {
            if let value = view as? WheelInteractionSurface.CursorView { return value }
            return view.subviews.lazy.compactMap(surface).first
        }
        let input = try XCTUnwrap(window.contentView.flatMap(surface))
        XCTAssertTrue(input.enabled.isEmpty)
        XCTAssertFalse(input.canReorder)
        XCTAssertFalse(input.centerEnabled)
        input.click?(0)
        XCTAssertEqual(selected, 0); XCTAssertFalse(window.isVisible)
    }

    func testLazyEditorRevealsNewColumnAndMoreSpacesOffscreen() async throws {
        try requireOffscreen()
        let model = heldMatrixFixture(count: 24, displayCount: 2)
        let window = hiddenWindow(CurrentConnectionsView(model: model, showsDesktopSources: true))
        defer { window.close() }
        try await waitUntil { self.element("connections-add", in: window) != nil }
        try press("connections-add", in: window)
        try await waitUntil { self.visible("connection-new-hint", in: window) }
        try press("connection-more-spaces-mac", in: window)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertFalse(model.isSwitching); XCTAssertFalse(window.isVisible)
    }

    func testSpacePickerReadsNewSpacesInsteadOfCachedStatusOffscreen() async throws {
        try requireOffscreen()
        let model = heldMatrixFixture(count: 2)
        model.displayLayout = .init(displays: model.displayLayout.displays.filter { $0.id == "mac" })
        let cached = try XCTUnwrap(model.workspaceLatestObservation)
        let latest = heldMatrixObservation(order: [0, 1, 2])
        model.workspaceObservationOverride = { latest }
        let window = hiddenWindow(ConnectionSpacePicker(model: model, context: nil, displayID: "mac", close: {}))
        defer { window.close() }
        try await waitUntil { self.element("connection-choice-mac-2", in: window) != nil }
        XCTAssertEqual(model.workspaceLatestObservation, cached, "Opening the picker should not require a global status refresh")
        XCTAssertFalse(model.isSwitching); XCTAssertFalse(window.isVisible)
    }

    private func requireOffscreen() throws {
        guard ProcessInfo.processInfo.environment["SIDEBY_OFFSCREEN_EVIDENCE"] == "1" else { throw XCTSkip("Opt-in offscreen view tests") }
        NSApplication.shared.perform(NSSelectorFromString("accessibilitySetValue:forAttribute:"), with: NSNumber(value: true), with: "AXEnhancedUserInterface")
    }
    private func hiddenWindow<Content: View>(_ content: Content) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 680), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content)
        window.contentView?.layoutSubtreeIfNeeded()
        return window
    }
    private func element(_ id: String, in window: NSWindow) -> NSObject? {
        func find(_ object: NSObject) -> NSObject? {
            if object.responds(to: NSSelectorFromString("accessibilityIdentifier")),
               object.perform(NSSelectorFromString("accessibilityIdentifier"))?.takeUnretainedValue() as? String == id { return object }
            if object.responds(to: NSSelectorFromString("accessibilityChildren")),
               let children = object.perform(NSSelectorFromString("accessibilityChildren"))?.takeUnretainedValue() as? [NSObject] {
                return children.lazy.compactMap(find).first
            }
            return nil
        }
        return window.contentView.flatMap(find)
    }
    private func visible(_ id: String, in window: NSWindow) -> Bool {
        guard let element = element(id, in: window) as? any NSAccessibilityElementProtocol else { return false }
        let frame = element.accessibilityFrame()
        return frame.width > 0 && frame.height > 0 && window.frame.intersects(frame)
    }
    private func press(_ id: String, in window: NSWindow) throws {
        let object = try XCTUnwrap(element(id, in: window), id)
        if let button = object as? NSButton { button.performClick(nil); return }
        let selector = NSSelectorFromString("accessibilityPerformPress")
        XCTAssertTrue(object.responds(to: selector))
        let action = unsafeBitCast(try XCTUnwrap(object.method(for: selector)), to: (@convention(c) (AnyObject, Selector) -> Bool).self)
        XCTAssertTrue(action(object, selector))
    }
    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<150 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Condition not reached", file: file, line: line)
    }
}

private final class BlockingSwitcherTitles: SpaceNameSuggestionProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var main = false
    private var returned = false
    let resume = DispatchSemaphore(value: 0)
    var readCount: Int { lock.withLock { count } }
    var calledOnMain: Bool { lock.withLock { main } }
    var hasReturned: Bool { lock.withLock { returned } }
    func names(for layout: DisplayLayout, spaceIDsByDisplayID: [String: [UInt64]]) -> [String: [Int: String]] {
        lock.withLock { count += 1; main = main || Thread.isMainThread }
        _ = resume.wait(timeout: .now() + 5)
        lock.withLock { returned = true }
        return ["mac": [0: "Refreshed title"]]
    }
}
