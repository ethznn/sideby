import AppKit
import SidebyCore
import SwiftUI
import Vision
import XCTest
@testable import SidebyApp

@MainActor final class HeldWorkspaceWheelNativeTests: XCTestCase {
    private func requireOffscreenRendering() throws {
        guard ProcessInfo.processInfo.environment["SIDEBY_OFFSCREEN_EVIDENCE"] == "1" else {
            throw XCTSkip("Opt-in offscreen rendering; no visible windows or system input")
        }
        prepareAccessibilityTree()
    }

    private func prepareAccessibilityTree() {
        NSApplication.shared.perform(NSSelectorFromString("accessibilitySetValue:forAttribute:"), with: NSNumber(value: true), with: "AXEnhancedUserInterface")
    }

    private func requireNative() throws {
        // Rendering evidence alone must never authorize moving the real pointer
        // or activating windows on the user's desktop.
        guard ProcessInfo.processInfo.environment["SIDEBY_NATIVE_EVIDENCE"] == "1",
              ProcessInfo.processInfo.environment["SIDEBY_INTERACTIVE_UI_TESTS"] == "1" else {
            throw XCTSkip("Visible/input tests require a separately authorized interactive test session")
        }
        prepareAccessibilityTree()
        let policy = NSApp.activationPolicy(), previous = NSWorkspace.shared.frontmostApplication
        let pointer = CGEvent(source: nil)?.location
        NSApp.setActivationPolicy(.accessory)
        addTeardownBlock { await MainActor.run {
            NSApp.setActivationPolicy(policy); _ = previous?.activate(options: [])
            if let pointer { CGWarpMouseCursorPosition(pointer) }
        } }
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

    private func click(_ point: NSPoint, in window: NSWindow) throws {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            window.sendEvent(try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1)))
        }
    }

    private func click(_ id: String, in window: NSWindow) throws {
        let object = try XCTUnwrap(element(id, in: window), id)
        let rect = try XCTUnwrap(object as? any NSAccessibilityElementProtocol).accessibilityFrame()
        try click(window.convertPoint(fromScreen: NSPoint(x: rect.midX, y: rect.midY)), in: window)
    }

    private func key(_ code: UInt16, text: String, in window: NSWindow) throws {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            window.sendEvent(try XCTUnwrap(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)))
        }
    }

    private func hover(_ point: NSPoint, in window: NSWindow) async throws {
        try XCTSkipUnless(CGPreflightPostEventAccess(), "Native hover requires existing input permission")
        let screenPoint = window.convertPoint(toScreen: point)
        let cgPoint = CGPoint(x: screenPoint.x, y: NSScreen.screens[0].frame.maxY - screenPoint.y)
        let feed = Task.detached {
            try await Task.sleep(for: .milliseconds(80))
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: cgPoint, mouseButton: .left)?.post(tap: .cghidEventTap)
            try await Task.sleep(for: .milliseconds(180))
            DispatchQueue.main.async {
                NSApp.stop(nil)
                if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                    windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) { NSApp.postEvent(event, atStart: true) }
            }
        }
        CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) { MainActor.assumeIsolated { NSApp.run() } }
        CFRunLoopWakeUp(CFRunLoopGetMain())
        try await feed.value
    }

    private func capture(_ name: String, window: NSWindow) throws {
        let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SIDEBY_NATIVE_EVIDENCE_OUTPUT"] ?? "/tmp/sideby-wheel-native.noindex")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let host = try XCTUnwrap(window.contentView)
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        if name == "wheel-count-8" {
            let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
            func alpha(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
                bitmap.colorAt(x: Int(x * scale), y: Int(y * scale))?.alphaComponent ?? 1
            }
            XCTAssertEqual(alpha(0, 0), 0, accuracy: 0.01, "Outside HUD is transparent")
            XCTAssertEqual(alpha(325, 228), 0, accuracy: 0.01, "Center-to-sector gap is transparent")
            XCTAssertEqual(alpha(290, 99), 0, accuracy: 0.01, "Sector gap is transparent")
            XCTAssertGreaterThan(alpha(236, 228), 0.99, "Center control remains legible")
        }
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: folder.appendingPathComponent(name + ".png"))
    }

    /// Exercise the actual AppKit tracker without moving the user's pointer.
    private func trackPointer(_ point: NSPoint, in window: NSWindow, canvasDiameter: CGFloat = 440) async throws {
        func find(_ view: NSView) -> NSView? {
            if String(describing: type(of: view)) == "CursorView" { return view }
            return view.subviews.lazy.compactMap(find).first
        }
        let tracker = try XCTUnwrap(window.contentView.flatMap(find))
        let local = NSPoint(x: point.x * tracker.bounds.width / canvasDiameter, y: point.y * tracker.bounds.height / canvasDiameter)
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: tracker.convert(local, to: nil),
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
        tracker.mouseMoved(with: event)
        try await Task.sleep(for: .milliseconds(200))
        window.contentView?.layoutSubtreeIfNeeded()
    }

    private func centerValue(in window: NSWindow) throws -> String {
        let center = try XCTUnwrap(element("held-add-current-connection", in: window))
        return center.perform(NSSelectorFromString("accessibilityValue"))?.takeUnretainedValue() as? String ?? ""
    }

    private func centerFill(in window: NSWindow) throws -> NSColor {
        try fill(at: NSPoint(x: 298, y: 220), in: window)
    }

    private func fill(at point: NSPoint, in window: NSWindow) throws -> NSColor {
        let host = try XCTUnwrap(window.contentView)
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
        return try XCTUnwrap(bitmap.colorAt(x: Int((16 + point.x) * scale), y: Int((8 + point.y) * scale))?.usingColorSpace(.deviceRGB))
    }

    private func colorDifference(_ lhs: NSColor, _ rhs: NSColor) -> CGFloat {
        abs(lhs.redComponent - rhs.redComponent) + abs(lhs.greenComponent - rhs.greenComponent)
            + abs(lhs.blueComponent - rhs.blueComponent)
    }

    func testOnlyHoveredTargetIsHighlightedAndCenterShowsBothSpacesIncludingCurrentConnection() async throws {
        try requireOffscreenRendering()
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let model = heldMatrixFixture(count: 4, displayCount: 2)
            model.workspacePreferences = nil
            model.workspaceDesktopNames["mac"] = [0: "Checkout.swift", 1: "Checkout PR #42", 2: "Operations"]
            model.workspaceDesktopNames["external-1"] = [0: "Checkout API", 1: "Checkout preview", 2: "Metrics"]
            let before = model.settings, observed = model.workspaceLastObservedSpaceKeys
            let window = window(HeldWorkspaceWheelView(model: model, select: { _ in XCTFail("Hover never switches") }), visible: false)
            window.appearance = NSAppearance(named: appearance)
            defer { window.close() }
            try await Task.sleep(for: .milliseconds(500))
            XCTAssertFalse(window.isVisible)
            let top = NSPoint(x: 220, y: 20), right = NSPoint(x: 420, y: 220), bottom = NSPoint(x: 220, y: 420)
            try await trackPointer(.zero, in: window)
            let neutral = try fill(at: right, in: window)
            XCTAssertLessThan(try colorDifference(fill(at: top, in: window), neutral), 0.02,
                "Current connection must not compete with the hovered target")
            XCTAssertLessThan(try colorDifference(centerFill(in: window), neutral), 0.02)
            try capture("wheel-states-\(appearance.rawValue)-neutral", window: window)

            var activeFill: NSColor?
            for (index, point, titles) in [
                (0, top, ["Checkout.swift", "Checkout API"]),
                (1, right, ["Checkout PR #42", "Checkout preview"]),
                (2, bottom, ["Operations", "Metrics"]),
                (0, top, ["Checkout.swift", "Checkout API"])
            ] {
                try await trackPointer(HeldWorkspaceWheelLayout.labelPoint(index: index, count: 4), in: window)
                let value = try centerValue(in: window)
                for title in titles { XCTAssertTrue(value.contains(title), "Center must include each display's actual Space content") }
                XCTAssertTrue(value.contains("MacBook Pro")); XCTAssertTrue(value.contains("Studio Display"))
                let hovered = try fill(at: point, in: window)
                XCTAssertGreaterThan(colorDifference(hovered, neutral), 0.08)
                if let activeFill { XCTAssertLessThan(colorDifference(hovered, activeFill), 0.02) }
                activeFill = hovered
                for other in [top, right, bottom] where other != point {
                    XCTAssertLessThan(try colorDifference(fill(at: other, in: window), neutral), 0.02,
                        "Only one sector may have hover emphasis")
                }
                XCTAssertLessThan(try colorDifference(centerFill(in: window), neutral), 0.02,
                    "Center is a neutral content preview while an outer sector is hovered")
                try capture("wheel-states-\(appearance.rawValue)-preview-\(index)", window: window)
            }

            try await trackPointer(NSPoint(x: 220, y: 220), in: window)
            let button = try XCTUnwrap(element("held-add-current-connection", in: window))
            XCTAssertEqual(button.perform(NSSelectorFromString("accessibilityLabel"))?.takeUnretainedValue() as? String, "현재 상태 추가하기")
            XCTAssertFalse(try centerValue(in: window).contains("Checkout"))
            XCTAssertLessThan(try colorDifference(centerFill(in: window), XCTUnwrap(activeFill)), 0.02,
                "Center uses exactly the same highlight as outer sectors")
            for point in [top, right, bottom] { XCTAssertLessThan(try colorDifference(fill(at: point, in: window), neutral), 0.02) }
            try capture("wheel-states-\(appearance.rawValue)-center", window: window)

            // Keyboard focus still previews the destination, but pointer exit wins
            // even if that key focus remains on the control.
            window.selectNextKeyView(nil)
            try await Task.sleep(for: .milliseconds(150))
            try await trackPointer(NSPoint(x: 220, y: 130), in: window)
            XCTAssertEqual(try centerValue(in: window), "")
            for point in [top, right, bottom] { XCTAssertLessThan(try colorDifference(fill(at: point, in: window), neutral), 0.02) }
            XCTAssertLessThan(try colorDifference(centerFill(in: window), neutral), 0.02)
            XCTAssertEqual(model.settings, before); XCTAssertEqual(model.workspaceLastObservedSpaceKeys, observed)
        }
    }

    func testCenterHoverHighlightsAndSectorPreviewsFollowPointerWithoutChangingConnections() async throws {
        try requireOffscreenRendering()
        for language in [AppLanguage.korean, .english] {
            for count in [0, 4] {
                let model = heldMatrixFixture(count: max(1, count), displayCount: 2)
                model.settings.language = language; model.workspacePreferences = nil
                if count == 0 { model.settings.contextPlan = .empty; model.settings.savedWorkspaces.bookmarks = [:] }
                let before = model.settings, observed = model.workspaceLastObservedSpaceKeys
                let window = window(HeldWorkspaceWheelView(model: model,
                    select: { _ in XCTFail("Hover must never switch Spaces") }), visible: false)
                window.appearance = NSAppearance(named: .darkAqua)
                defer { window.close() }
                try await Task.sleep(for: .milliseconds(500))
                try await trackPointer(.zero, in: window)
                let normal = try centerFill(in: window)
                try await trackPointer(NSPoint(x: 220, y: 220), in: window)
                let highlighted = try centerFill(in: window)
                let difference = abs(normal.redComponent - highlighted.redComponent)
                    + abs(normal.greenComponent - highlighted.greenComponent) + abs(normal.blueComponent - highlighted.blueComponent)
                XCTAssertGreaterThan(difference, 0.03, "Center must visibly respond, not only change the cursor")
                XCTAssertTrue(try centerValue(in: window).contains(language == .korean ? "지금 보고 있는 Space" : "currently on your displays"))
                try capture("wheel-center-hover-\(language)-\(count)", window: window)
                if count > 0 {
                    for index in [1, 2] {
                        try await trackPointer(HeldWorkspaceWheelLayout.labelPoint(index: index, count: count), in: window)
                        let preview = try centerValue(in: window)
                        XCTAssertTrue(preview.contains(index == 1 ? "Review" : "Operations"))
                        XCTAssertTrue(preview.contains(index == 1 ? "변경 사항 검토" : "운영 대시보드"))
                        try capture("wheel-center-preview-\(language)-\(index)", window: window)
                    }
                    try await trackPointer(NSPoint(x: 220, y: 220), in: window)
                    XCTAssertFalse(try centerValue(in: window).contains("Operations"), "Center hover restores the save action")
                    try await trackPointer(NSPoint(x: 220, y: 130), in: window)
                    XCTAssertEqual(try centerValue(in: window), "", "Transparent gap has no connection preview")
                }
                XCTAssertEqual(model.settings, before)
                XCTAssertEqual(model.workspaceLastObservedSpaceKeys, observed)
            }
        }
    }

    func testSmallCenterPreviewHandlesLongNamesManyDisplaysAndEmptyConnections() async throws {
        try requireOffscreenRendering()
        let model = heldMatrixFixture(count: 8, displayCount: 3)
        model.workspacePreferences = nil
        var contexts = model.settings.contextPlan.contexts
        contexts[1] = contexts[1].renamed("매우 긴 연결 이름 · 결제 화면 개발과 변경 사항을 검토하는 작업")
        model.settings.contextPlan.replaceContexts(contexts, currentContextID: "work-0")
        var edits = 0
        let window = window(HeldWorkspaceWheelView(model: model, select: { _ in XCTFail("Preview never switches") },
            edit: { _ in edits += 1 }, diameter: 320), size: NSSize(width: 352, height: 448), visible: false)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(500))
        let frame = window.frame, before = model.settings
        let geometry = HeldWorkspaceWheelGeometry(displayCount: 3)
        let point = HeldWorkspaceWheelLayout.labelPoint(index: 1, count: 8, geometry: geometry)
        try await trackPointer(point, in: window, canvasDiameter: geometry.diameter)
        XCTAssertTrue(try centerValue(in: window).contains(contexts[1].name))
        try capture("wheel-center-small-long-preview", window: window)
        XCTAssertEqual(window.frame, frame); XCTAssertEqual(model.settings, before)

        contexts[1] = .init(id: "work-1", order: 2, name: "Empty", displaySpaceIndexes: [:])
        model.settings.contextPlan.replaceContexts(contexts, currentContextID: "work-0")
        model.settings.savedWorkspaces.bookmarks["work-1"] = [:]
        model.refreshWorkspaceStatus()
        try await Task.sleep(for: .milliseconds(150))
        try await trackPointer(point, in: window, canvasDiameter: geometry.diameter)
        XCTAssertTrue(try centerValue(in: window).contains("연결된 참여 모니터가 없습니다"))
        try capture("wheel-center-small-empty-preview", window: window)
        let emptyButton = try XCTUnwrap(element("wheel-go-work-1", in: window))
        // SwiftUI exposes the public AX action without adopting the AppKit
        // NSAccessibilityButton protocol. Call its BOOL-returning method directly.
        let press = NSSelectorFromString("accessibilityPerformPress")
        XCTAssertTrue(emptyButton.responds(to: press))
        let implementation = try XCTUnwrap(emptyButton.method(for: press))
        let performPress = unsafeBitCast(implementation, to: (@convention(c) (AnyObject, Selector) -> Bool).self)
        XCTAssertTrue(performPress(emptyButton, press))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(edits, 1, "Empty sector still leads to editing, not a save action")
        XCTAssertEqual(window.frame, frame)
    }

    func testThreeAndMoreDisplaysAreActuallyRenderedAndHoverDoesNotResize() async throws {
        try requireOffscreenRendering()
        for language in [AppLanguage.korean, .english] {
            for displayCount in [3, 4, 6] {
                let model = heldMatrixFixture(count: 4, displayCount: displayCount)
                model.workspacePreferences = nil; model.settings.language = language
                let geometry = HeldWorkspaceWheelGeometry(displayCount: displayCount)
                let snapshot = HeldWorkspaceSnapshot(model: model)
                let titles = ["Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot"]
                for (index, id) in snapshot.displayIDs.enumerated() {
                    model.workspaceDesktopNames[id] = [0: titles[index], 1: "Notes"]
                }
                var contexts = model.settings.contextPlan.contexts
                contexts[1] = .init(id: "work-1", order: 2, name: "One display",
                    displaySpaceIndexes: [snapshot.displayIDs[0]: 1])
                model.settings.contextPlan.replaceContexts(contexts, currentContextID: "work-0")
                model.settings.savedWorkspaces.bookmarks["work-1"] = [
                    snapshot.displayIDs[0]: try XCTUnwrap(model.workspaceLastObservedSpaceKeys[snapshot.displayIDs[0]]?[1])
                ]
                model.refreshWorkspaceStatus()
                let before = model.settings
                let window = window(HeldWorkspaceWheelView(model: model,
                    select: { _ in XCTFail("Preview never switches") }),
                    size: NSSize(width: geometry.diameter + 32, height: geometry.diameter + 128), visible: false)
                window.appearance = NSAppearance(named: language == .korean ? .darkAqua : .aqua)
                defer { window.close() }
                try await Task.sleep(for: .milliseconds(400))
                let frame = window.frame
                try await trackPointer(HeldWorkspaceWheelLayout.labelPoint(index: 0, count: 4, geometry: geometry),
                    in: window, canvasDiameter: geometry.diameter)
                let center = try XCTUnwrap(element("held-add-current-connection", in: window) as? any NSAccessibilityElementProtocol)
                let centerFrame = center.accessibilityFrame()
                try capture("wheel-displays-\(language)-\(displayCount)", window: window)

                // Read the rendered center pixels, not its AX description (which
                // already contained hidden displays before this change).
                let host = try XCTUnwrap(window.contentView)
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate; request.recognitionLanguages = ["en-US"]
                request.usesLanguageCorrection = false
                try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage), options: [:]).perform([request])
                let rendered = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                for title in titles.prefix(displayCount) {
                    XCTAssertTrue(rendered.contains(title), "Every display must appear in the image: \(title)\n\(rendered)")
                }
                for point in [
                    HeldWorkspaceWheelLayout.labelPoint(index: 1, count: 4, geometry: geometry),
                    NSPoint(x: geometry.midpoint, y: geometry.midpoint),
                    HeldWorkspaceWheelLayout.labelPoint(index: 0, count: 4, geometry: geometry)
                ] {
                    try await trackPointer(point, in: window, canvasDiameter: geometry.diameter)
                    let latest = try XCTUnwrap(element("held-add-current-connection", in: window) as? any NSAccessibilityElementProtocol)
                    XCTAssertEqual(latest.accessibilityFrame(), centerFrame, "Partial/full/save previews keep the same center size")
                    XCTAssertEqual(window.frame, frame)
                }
                XCTAssertFalse(window.isVisible); XCTAssertEqual(model.settings, before)
            }
        }
    }

    func testLargerNamesAndWindowTitlesRenderOffscreenAtSparseDenseAndMinimumSizes() async throws {
        try requireOffscreenRendering()
        for language in [AppLanguage.korean, .english] {
            for (count, diameter) in [(2, 440.0), (4, 440.0), (8, 440.0), (8, 360.0), (8, 320.0)] {
                let model = heldMatrixFixture(count: count, displayCount: 2)
                model.workspacePreferences = nil; model.settings.language = language
                let names = language == .korean
                    ? ["메모와 자료 정리", "결제 화면 개발", "검토와 피드백", "운영 대시보드"]
                    : ["Notes and research", "Checkout development", "Review and feedback", "Operations dashboard"]
                let contexts = model.settings.contextPlan.contexts.enumerated().map { index, context in
                    context.renamed(names[index % names.count])
                }
                model.settings.contextPlan.replaceContexts(contexts, currentContextID: "work-0")
                model.workspaceDesktopNames["mac"] = [0: "Notes — Project ideas", 1: "Checkout — Payment confirmation"]
                model.workspaceDesktopNames["external-1"] = [0: "Research browser", 1: "Preview — Test payment completed"]
                let before = model.settings
                let size = NSSize(width: diameter + 32, height: diameter + 128)
                let window = window(HeldWorkspaceWheelView(model: model,
                    select: { _ in XCTFail("Rendering must never switch") }, diameter: diameter), size: size, visible: false)
                window.appearance = NSAppearance(named: language == .korean ? .darkAqua : .aqua)
                defer { window.close() }
                try await Task.sleep(for: .milliseconds(400))
                XCTAssertFalse(window.isVisible)
                for index in [0, 1] {
                    try await trackPointer(HeldWorkspaceWheelLayout.labelPoint(index: index, count: count), in: window)
                    let button = try XCTUnwrap(element("wheel-go-work-\(index)", in: window))
                    let label = button.perform(NSSelectorFromString("accessibilityLabel"))?.takeUnretainedValue() as? String ?? ""
                    XCTAssertTrue(label.contains(names[index]), "Full names remain available even if visible text is truncated")
                    if index == 1 {
                        XCTAssertTrue(try centerValue(in: window).contains("Payment confirmation"))
                        XCTAssertTrue(try centerValue(in: window).contains("Test payment completed"))
                    }
                    try capture("wheel-readable-\(language)-\(count)-\(Int(diameter))-\(index)", window: window)
                }
                XCTAssertEqual(window.frame.size, size); XCTAssertEqual(model.settings, before)
            }
        }
    }

    func testQuickTableNamesItsActionAndStillDelegatesTheWholeConnectionOffscreen() async throws {
        try requireOffscreenRendering()
        for language in [AppLanguage.korean, .english] {
            let model = heldMatrixFixture(count: 3, displayCount: 2)
            model.workspacePreferences = nil; model.settings.language = language
            let before = model.settings.savedWorkspaces
            var selected: [String] = []
            let window = window(HeldWorkspaceMatrixView(model: model, snapshot: .init(model: model),
                select: { selected.append($0.id) }), size: .init(width: 760, height: 440), visible: false)
            defer { window.close() }
            try await Task.sleep(for: .milliseconds(350))
            try capture("table-explicit-action-\(language)", window: window)
            let cell = try XCTUnwrap(element("held-cell-work-2-mac", in: window))
            let label = cell.perform(NSSelectorFromString("accessibilityLabel"))?.takeUnretainedValue() as? String ?? ""
            XCTAssertTrue(label.contains(HeldMatrixStrings(language: language).move("Operations")),
                          "A cell explains that it activates the whole connection, not only its display")
            try pressOffscreen("held-go-work-1", in: window)
            try pressOffscreen("held-cell-work-2-mac", in: window)
            XCTAssertEqual(selected, ["work-1", "work-2"])
            XCTAssertEqual(model.settings.savedWorkspaces, before)
            XCTAssertFalse(window.isVisible)
        }
    }

    func testIdleGuidanceMatchesAvailableActionsAtZeroOneAndTwoConnectionsOffscreen() async throws {
        try requireOffscreenRendering()
        for language in [AppLanguage.korean, .english] {
            for count in [0, 1, 2] {
                let model = heldMatrixFixture(count: count, displayCount: 2)
                model.workspacePreferences = nil; model.settings.language = language
                let window = window(HeldWorkspaceWheelView(model: model,
                    select: { _ in XCTFail("Idle guidance must never activate a connection") }, diameter: 320),
                    size: .init(width: 352, height: 448), visible: false)
                defer { window.close() }
                try await Task.sleep(for: .milliseconds(350))
                let message = try XCTUnwrap(element("wheel-idle-guidance", in: window))
                let label = (message.perform(NSSelectorFromString("accessibilityLabel"))?.takeUnretainedValue() as? String)
                    ?? (message.perform(NSSelectorFromString("accessibilityValue"))?.takeUnretainedValue() as? String) ?? ""
                let expected = language == .korean
                    ? ["첫 연결", "돌아오세요", "순서 변경"][count]
                    : ["Start with", "return after", "reorder"][count]
                XCTAssertTrue(label.contains(expected), label)
                try capture("wheel-idle-\(language)-\(count)", window: window)
                XCTAssertFalse(window.isVisible)
            }
        }
    }

    private func window<Content: View>(_ view: Content, size: NSSize = NSSize(width: 472, height: 568),
                                       visible: Bool = true) -> HeldMatrixPanel {
        let screen = NSScreen.main!.visibleFrame
        let window = HeldMatrixPanel(contentRect: NSRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2,
            width: size.width, height: size.height), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.acceptsKeyboard = true; window.level = .popUpMenu
        window.backgroundColor = .clear; window.isOpaque = false; window.hasShadow = false
        window.contentView = HeldMatrixHostingView(rootView: view)
        window.contentView?.layoutSubtreeIfNeeded()
        if visible {
            NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
        }
        return window
    }

    func testHoverRenameImmediateDeleteUndoAndCenterCaptureNeverSwitch() async throws {
        try requireNative()
        for language in [AppLanguage.korean, .english] {
            let model = heldMatrixFixture(count: 4, displayCount: 2)
            model.settings.language = language; model.workspacePreferences = nil
            let before = model.settings, observed = model.workspaceLastObservedSpaceKeys
            var switches = 0, pins = 0
            let window = window(HeldWorkspaceWheelView(model: model, select: { _ in switches += 1 }, keepOpen: { pins += 1 }))
            defer { window.close() }
            try await Task.sleep(for: .milliseconds(600))
            let point = HeldWorkspaceWheelLayout.labelPoint(index: 1, count: 4)
            let hoverPoint = NSPoint(x: 16 + point.x, y: 568 - 8 - point.y)
            try await hover(hoverPoint, in: window)
            try capture("wheel-\(language)-hover", window: window)
            try click("wheel-rename-work-1", in: window)
            try await Task.sleep(for: .milliseconds(120))
            XCTAssertNotNil(element("connection-name-field", in: window)); XCTAssertGreaterThan(pins, 0)
            XCTAssertEqual(switches, 0)
            try click("connection-name-cancel", in: window)
            try await Task.sleep(for: .milliseconds(100))
            try await hover(hoverPoint, in: window)
            try click("wheel-delete-work-1", in: window)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertNil(element("wheel-delete-confirmation", in: window))
            XCTAssertNil(window.attachedSheet)
            try capture("wheel-\(language)-deleted-undo", window: window)
            XCTAssertEqual(model.settings.contextPlan.contexts.map(\.id), ["work-0", "work-2", "work-3"])
            XCTAssertEqual(model.workspaceLastObservedSpaceKeys, observed); XCTAssertEqual(switches, 0)
            try click("held-undo-connection", in: window)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(model.settings.contextPlan.contexts, before.contextPlan.contexts)
            let bounds = window.frame
            try click("held-add-current-connection", in: window)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(model.settings.contextPlan.contexts.last?.displayIDs.sorted(), ["external-1", "mac"])
            XCTAssertEqual(model.workspaceLastObservedSpaceKeys, observed)
            XCTAssertEqual(window.frame, bounds); XCTAssertEqual(switches, 0)
            XCTAssertNotNil(element("held-add-feedback", in: window))
            let columns = HeldWorkspaceSnapshot(model: model).columns
            let reviewIndex = try XCTUnwrap(columns.firstIndex { $0.id == "work-1" })
            try await trackPointer(HeldWorkspaceWheelLayout.labelPoint(index: reviewIndex, count: columns.count), in: window)
            XCTAssertTrue(try centerValue(in: window).contains("Review"), "Saving must not leave center focus overriding later sector previews")
        }
    }

    func testSectorBodySwitchesAndDoesNotRenameOrDelete() async throws {
        try requireNative()
        let model = heldMatrixFixture(count: 4)
        var selected: [String] = []
        let before = model.settings
        let window = window(HeldWorkspaceWheelView(model: model, select: { selected.append($0.id) }))
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(500))
        let point = HeldWorkspaceWheelLayout.labelPoint(index: 1, count: 4)
        try click(NSPoint(x: 16 + point.x, y: 568 - 8 - point.y + 10), in: window)
        XCTAssertEqual(selected, ["work-1"])
        XCTAssertEqual(model.settings, before)
        XCTAssertNil(element("connection-name-field", in: window))
        try click(NSPoint(x: 325, y: 568 - 228), in: window)
        XCTAssertEqual(selected, ["work-1"], "Transparent gaps do not select or capture")
        XCTAssertEqual(model.settings, before)
    }

    func testCurrentPartialConnectionExplainsCoverageAndClickClosesWithoutSwitching() async throws {
        try requireNative()
        let model = heldMatrixFixture(count: 3, displayCount: 2)
        model.workspacePreferences = nil
        var contexts = model.settings.contextPlan.contexts
        contexts[0] = .init(id: "work-0", order: 1, name: "연결 1", displaySpaceIndexes: ["mac": 0])
        model.settings.contextPlan.replaceContexts(contexts, currentContextID: "work-0")
        model.settings.savedWorkspaces.bookmarks["work-0"] = ["mac": model.workspaceLastObservedSpaceKeys["mac"]![0]]
        model.refreshWorkspaceStatus()
        let before = model.settings
        var closes = 0, edits = 0
        let window = window(HeldWorkspaceWheelView(model: model,
            select: { _ in XCTFail("The current partial connection never switches") },
            close: { closes += 1 }, edit: { _ in edits += 1 }))
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(500))
        let button = try XCTUnwrap(element("wheel-go-work-0", in: window))
        let label = button.perform(NSSelectorFromString("accessibilityLabel"))?.takeUnretainedValue() as? String ?? ""
        XCTAssertTrue(label.contains("이미 현재 Space"))
        XCTAssertTrue(label.contains("MacBook Pro만 연결"))
        XCTAssertTrue(label.contains("다른 모니터는 유지"))
        let point = HeldWorkspaceWheelLayout.labelPoint(index: 0, count: 3)
        try await hover(NSPoint(x: 16 + point.x, y: 568 - 8 - point.y), in: window)
        let summary = try XCTUnwrap(element("wheel-connection-summary", in: window) as? any NSAccessibilityElementProtocol)
        XCTAssertGreaterThan(summary.accessibilityFrame().height, 24, "Both status and display coverage must be visible")
        try capture("wheel-current-partial", window: window)
        try click(NSPoint(x: 16 + point.x, y: 568 - 8 - point.y + 10), in: window)
        XCTAssertEqual(closes, 1); XCTAssertEqual(edits, 0)
        XCTAssertEqual(model.settings, before)

        // A genuinely empty connection must offer setup, not an inert sector.
        contexts[0] = .init(id: "work-0", order: 1, name: "Empty", displaySpaceIndexes: [:])
        model.settings.contextPlan.replaceContexts(contexts, currentContextID: "work-1")
        model.settings.savedWorkspaces.bookmarks["work-0"] = [:]
        model.refreshWorkspaceStatus()
        try await Task.sleep(for: .milliseconds(100))
        try click(NSPoint(x: 16 + point.x, y: 568 - 8 - point.y + 10), in: window)
        XCTAssertEqual(edits, 1)
        XCTAssertEqual(closes, 1)
    }

    func testKeyboardCancelsClearAllAndRenameAppliesWithUndo() async throws {
        try requireNative()
        let model = heldMatrixFixture(count: 2, displayCount: 2)
        model.workspacePreferences = nil
        let before = model.settings
        var closes = 0
        let window = window(HeldWorkspaceWheelView(model: model, select: { _ in XCTFail("Editing must not switch") }, close: { closes += 1 }))
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(500))
        let point = HeldWorkspaceWheelLayout.labelPoint(index: 0, count: 2)
        let hoverPoint = NSPoint(x: point.x + 16, y: 568 - 8 - point.y)
        for (code, character) in [(UInt16(36), "\r"), (UInt16(53), "\u{1b}")] {
            try click("wheel-clear-all", in: window)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertNotNil(element("wheel-clear-all-confirmation", in: window))
            try key(code, text: character, in: window)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertNil(element("wheel-clear-all-confirmation", in: window), "Cancel key \(code), handler installed: \(window.cancelContent != nil)")
            XCTAssertEqual(model.settings, before); XCTAssertEqual(closes, 0)
        }
        try await hover(hoverPoint, in: window)
        try click("wheel-rename-work-0", in: window)
        try await Task.sleep(for: .milliseconds(100))
        let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
        editor.selectAll(nil); editor.insertText("집중 작업", replacementRange: editor.selectedRange())
        try await Task.sleep(for: .milliseconds(80))
        try click("connection-name-apply", in: window)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.settings.contextPlan.contexts.first?.name, "집중 작업")
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, before.savedWorkspaces.bookmarks)
        try click("held-undo-connection", in: window)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.settings.contextPlan.contexts, before.contextPlan.contexts)
    }

    func testEmptyOneTwoThreeEightAndPagingRenderAndKeepEveryConnection() async throws {
        try requireNative()
        for count in [0, 1, 2, 3, 8, 9] {
            let model = heldMatrixFixture(count: max(1, count), displayCount: 2)
            if count == 0 { model.settings.contextPlan = .init(contexts: [], currentContextID: ""); model.settings.savedWorkspaces.bookmarks = [:] }
            model.workspacePreferences = nil
            let window = window(HeldWorkspaceWheelView(model: model, select: { _ in XCTFail("Rendering never switches") }))
            window.appearance = NSAppearance(named: count % 2 == 0 ? .darkAqua : .aqua)
            defer { window.close() }
            try await Task.sleep(for: .milliseconds(500))
            try capture("wheel-count-\(count)", window: window)
            XCTAssertNotNil(element("held-add-current-connection", in: window))
            XCTAssertNotNil(element("held-undo-connection", in: window))
            XCTAssertNotNil(element("wheel-clear-all", in: window))
            if count == 0 {
                XCTAssertNotNil(element("wheel-empty-guidance", in: window))
                XCTAssertNotNil(element("wheel-empty-space-mac", in: window))
                XCTAssertNil(element("wheel-go-work-0", in: window), "Empty guidance must not create a saved connection")
            }
            if count == 9 {
                try click("wheel-next-page", in: window)
                try await Task.sleep(for: .milliseconds(100))
                XCTAssertNotNil(element("wheel-go-work-8", in: window))
                try capture("wheel-page-2", window: window)
            }
        }
    }

    func testClearAllEmptyStateFirstCaptureAndUndoRemainAvailableAfterReopening() async throws {
        try requireNative()
        for language in [AppLanguage.korean, .english] {
            let model = heldMatrixFixture(count: 3, displayCount: 2)
            model.settings.language = language; model.workspacePreferences = nil
            let before = model.settings, observed = model.workspaceLastObservedSpaceKeys
            var pins = 0
            let window = window(HeldWorkspaceWheelView(model: model,
                select: { _ in XCTFail("Managing connections never switches Spaces") }, keepOpen: { pins += 1 }))
            defer { window.close() }
            try await Task.sleep(for: .milliseconds(500))
            let originalFrame = window.frame
            try click("wheel-clear-all", in: window)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(model.settings, before)
            try capture("wheel-\(language)-clear-all-confirm", window: window)
            try click("wheel-confirm-clear-all", in: window)
            try await Task.sleep(for: .milliseconds(120))
            XCTAssertTrue(model.settings.contextPlan.contexts.isEmpty)
            XCTAssertNotNil(element("wheel-empty-guidance", in: window))
            XCTAssertNotNil(element("wheel-empty-space-mac", in: window))
            XCTAssertEqual(window.frame, originalFrame)
            XCTAssertGreaterThan(pins, 0, "Deletion must keep the held menu open for recovery")
            try capture("wheel-\(language)-empty-after-clear", window: window)

            // Reopening discards local feedback flags; undo must still be discoverable.
            window.contentView = HeldMatrixHostingView(rootView: HeldWorkspaceWheelView(model: model,
                select: { _ in XCTFail("Undo never switches Spaces") }))
            try await Task.sleep(for: .milliseconds(500))
            try click("held-undo-connection", in: window)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(model.settings.contextPlan.contexts, before.contextPlan.contexts)
            XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, before.savedWorkspaces.bookmarks)

            try click("wheel-clear-all", in: window)
            try await Task.sleep(for: .milliseconds(100))
            try click("wheel-confirm-clear-all", in: window)
            try await Task.sleep(for: .milliseconds(100))
            try click("held-add-current-connection", in: window)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(model.settings.contextPlan.contexts.count, 1)
            XCTAssertEqual(model.settings.contextPlan.contexts[0].displayIDs.sorted(), ["external-1", "mac"])
            XCTAssertNil(element("wheel-empty-guidance", in: window))
            XCTAssertEqual(window.frame, originalFrame)
            XCTAssertEqual(model.workspaceLastObservedSpaceKeys, observed)
            let onlyID = model.settings.contextPlan.contexts[0].id
            let point = HeldWorkspaceWheelLayout.labelPoint(index: 0, count: 1)
            try await hover(NSPoint(x: point.x + 16, y: 568 - 8 - point.y), in: window)
            try click("wheel-delete-" + onlyID, in: window)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertTrue(model.settings.contextPlan.contexts.isEmpty, "The last connection is deleted without confirmation")
            XCTAssertNotNil(element("wheel-empty-guidance", in: window))
            try click("held-undo-connection", in: window)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(model.settings.contextPlan.contexts.map(\.id), [onlyID])
            try click("held-undo-connection", in: window)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertTrue(model.settings.contextPlan.contexts.isEmpty)
            try click("held-undo-connection", in: window)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(model.settings.contextPlan.contexts, before.contextPlan.contexts)
        }
    }

    func testSmallWheelKeepsCleanupUndoAndFirstConnectionInsideWindow() async throws {
        try requireNative()
        for language in [AppLanguage.korean, .english] {
            for count in [0, 9] {
                let model = heldMatrixFixture(count: max(1, count), displayCount: 2)
                model.settings.language = language; model.workspacePreferences = nil
                if count == 0 {
                    model.settings.contextPlan = .empty
                    model.settings.savedWorkspaces.bookmarks = [:]
                }
                let window = window(HeldWorkspaceWheelView(model: model, select: { _ in }, diameter: 320),
                    size: NSSize(width: 352, height: 448))
                defer { window.close() }
                try await Task.sleep(for: .milliseconds(500))
                for id in ["held-edit-connections", "wheel-clear-all", "held-undo-connection", "held-add-current-connection"] {
                    let control = try XCTUnwrap(element(id, in: window) as? any NSAccessibilityElementProtocol)
                    XCTAssertTrue(window.frame.contains(control.accessibilityFrame()), "\(language), \(count), \(id) must fit")
                }
                try capture("wheel-small-\(language)-\(count)", window: window)
            }
        }
    }

    func testProductionControllerReturnsFromEditorToSamePointerAnchoredWheel() async throws {
        try requireNative()
        let model = heldMatrixFixture(count: 4, displayCount: 2)
        model.workspacePreferences = nil
        let controller = HeldWorkspaceMatrixController(model: model, preferences: MemoryProductUIPreferences())
        controller.showPersistent()
        let window = try XCTUnwrap(NSApp.windows.first { $0.isVisible && $0.identifier?.rawValue == "sideby-held-workspace-matrix" })
        defer { controller.dismiss(); window.close() }
        try await Task.sleep(for: .milliseconds(500))
        let original = window.frame
        XCTAssertNotNil(element("held-workspace-wheel", in: window))
        XCTAssertFalse(window.isOpaque)
        XCTAssertEqual(window.backgroundColor.alphaComponent, 0)
        XCTAssertFalse(window.hasShadow, "No rectangular window shadow around the HUD")
        try click("held-edit-connections", in: window)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNotNil(element("current-connections-table", in: window))
        XCTAssertNotNil(element("connection-space-count-mac", in: window))
        try capture("connections-native", window: window)
        try click("held-finish-editing", in: window)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(window.frame, original)
        XCTAssertNotNil(element("held-workspace-wheel", in: window))
        try click("wheel-show-table", in: window)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNotNil(element("held-switch-table", in: window))
        try click("held-show-wheel", in: window)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(window.frame, original)
    }
    private func pressOffscreen(_ id: String, in window: NSWindow) throws {
        let object = try XCTUnwrap(element(id, in: window), id)
        if let button = object as? NSButton {
            XCTAssertTrue(button.isEnabled)
            button.performClick(nil)
            return
        }
        let action = NSSelectorFromString("accessibilityPerformPress")
        XCTAssertTrue(object.responds(to: action))
        let implementation = try XCTUnwrap(object.method(for: action))
        let press = unsafeBitCast(implementation, to: (@convention(c) (AnyObject, Selector) -> Bool).self)
        XCTAssertTrue(press(object, action))
    }

    func testViewToggleStaysAtTopAndReturnsToCircleFromInitialTableOffscreen() async throws {
        try requireOffscreenRendering()
        for startsWithCircle in [true, false] {
            let model = heldMatrixFixture(count: 3, displayCount: 2)
            model.workspacePreferences = nil
            let before = model.settings
            var changes: [HeldSwitcherPresentation] = [], pins = 0
            let root = HeldWorkspaceMatrixView(model: model, snapshot: .init(model: model),
                select: { _ in XCTFail("Changing the view never switches Spaces") },
                keepOpen: { pins += 1 }, usesRadial: startsWithCircle,
                wheelDiameter: 440, presentationChanged: { changes.append($0) })
            let window = window(root, size: NSSize(width: 472, height: 608), visible: false)
            window.appearance = NSAppearance(named: .darkAqua)
            defer { window.close() }
            try await Task.sleep(for: .milliseconds(400))
            let control = try XCTUnwrap(element("wheel-show-table", in: window) as? any NSAccessibilityElementProtocol)
            let frame = control.accessibilityFrame()
            try pressOffscreen("held-edit-connections", in: window)
            try await Task.sleep(for: .milliseconds(350))
            XCTAssertNotNil(element("current-connections-table", in: window))
            for id in ["held-view-control", "wheel-show-table", "held-show-wheel"] {
                XCTAssertNil(element(id, in: window), "View choices belong to the switcher, not its editor")
            }
            let finish = try XCTUnwrap(element("held-finish-editing", in: window) as? any NSAccessibilityElementProtocol)
            XCTAssertLessThan(window.frame.maxY - finish.accessibilityFrame().maxY, HeldSwitcherViewControl.height,
                              "The hidden toolbar must not leave a blank strip above the editor")
            try capture("switcher-editor-no-tabs-\(startsWithCircle)", window: window)
            try pressOffscreen("held-finish-editing", in: window)
            try await Task.sleep(for: .milliseconds(350))
            XCTAssertNotNil(element(startsWithCircle ? "held-workspace-wheel" : "held-switch-table", in: window))
            for (id, content) in [("wheel-show-table", "held-switch-table"), ("held-show-wheel", "held-workspace-wheel")] {
                try pressOffscreen(id, in: window)
                try await Task.sleep(for: .milliseconds(350))
                window.contentView?.layoutSubtreeIfNeeded()
                XCTAssertNotNil(element(content, in: window))
                let button = try XCTUnwrap(element("wheel-show-table", in: window) as? any NSAccessibilityElementProtocol)
                XCTAssertEqual(button.accessibilityFrame().midX, frame.midX, accuracy: 1)
                XCTAssertEqual(button.accessibilityFrame().midY, frame.midY, accuracy: 1)
                try capture("switcher-toggle-\(startsWithCircle)-\(id)", window: window)
            }
            XCTAssertEqual(changes, startsWithCircle ? [.editor, .wheel, .table, .wheel] : [.editor, .table, .wheel])
            // Only actual editing pins: the wheel pins before the shared editor,
            // whereas changing presentation must preserve the current lifetime.
            XCTAssertEqual(pins, startsWithCircle ? 2 : 1)
            XCTAssertEqual(model.settings, before); XCTAssertFalse(window.isVisible)
        }
    }

    func testMissingSpaceOpensTargetedRepairBarWithoutSwitchingOffscreen() async throws {
        try requireOffscreenRendering()
        let model = heldMatrixFixture(count: 3, displayCount: 2)
        model.workspacePreferences = nil
        model.settings.savedWorkspaces.bookmarks["work-1"]?["mac"] = "missing-sample-space"
        model.refreshWorkspaceStatus()
        let before = model.settings.savedWorkspaces
        let window = window(HeldWorkspaceMatrixView(model: model, snapshot: .init(model: model),
            select: { _ in XCTFail("Repair entry must never move Spaces") },
            availableHeight: 580, usesRadial: true, wheelDiameter: 440),
            size: NSSize(width: 900, height: 580), visible: false)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(350))
        try pressOffscreen("wheel-go-work-1", in: window)
        try await Task.sleep(for: .milliseconds(350))
        let bar = try XCTUnwrap(element("connection-repair-bar", in: window) as? any NSAccessibilityElementProtocol)
        let choice = try XCTUnwrap(element("connection-repair-choose", in: window) as? any NSAccessibilityElementProtocol)
        XCTAssertTrue(window.frame.contains(bar.accessibilityFrame()), "The repair bar is pinned outside all table scroll views")
        XCTAssertTrue(bar.accessibilityFrame().contains(choice.accessibilityFrame()))
        try capture("targeted-repair-editor", window: window)
        model.isSwitching = true
        try await Task.sleep(for: .milliseconds(100))
        let disabledChoice = try XCTUnwrap(element("connection-repair-choose", in: window))
        let enabledSelector = NSSelectorFromString("isAccessibilityEnabled")
        XCTAssertTrue(disabledChoice.responds(to: enabledSelector))
        let enabledImplementation = try XCTUnwrap(disabledChoice.method(for: enabledSelector))
        let isEnabled = unsafeBitCast(enabledImplementation, to: (@convention(c) (AnyObject, Selector) -> Bool).self)
        XCTAssertFalse(isEnabled(disabledChoice, enabledSelector))
        model.isSwitching = false
        try pressOffscreen("connection-repair-dismiss", in: window)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertNil(element("connection-repair-bar", in: window))
        XCTAssertNotNil(element("current-connections-table", in: window))
        XCTAssertEqual(model.settings.savedWorkspaces, before)
        XCTAssertFalse(window.isVisible)
    }

    func testRecoveryNamesOriginalTargetAndKeepsGenericEditingOffscreen() async throws {
        try requireOffscreenRendering()
        let model = heldMatrixFixture(count: 10, displayCount: 2)
        model.workspacePreferences = nil
        model.workspaceRecoveryTargetID = "work-9"
        let window = window(HeldWorkspaceWheelView(model: model,
            select: { _ in XCTFail("Rendering recovery never moves Spaces") }, diameter: 320),
            size: NSSize(width: 352, height: 448), visible: false)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(350))
        try await trackPointer(HeldWorkspaceWheelLayout.labelPoint(index: 2, count: 8), in: window)
        let message = try XCTUnwrap(element("wheel-recovery-message", in: window))
        let label = message.perform(NSSelectorFromString("accessibilityLabel"))?.takeUnretainedValue() as? String ?? ""
        XCTAssertTrue(label.contains("Review"))
        XCTAssertNotNil(element("held-edit-connections", in: window))
        XCTAssertNotNil(element("wheel-recovery-action", in: window))
        try capture("recovery-off-page-minimum", window: window)
        XCTAssertFalse(window.isVisible)
    }

    func testWheelNativeDragWiringReordersAndUndoRestoresWithoutSwitchingOffscreen() async throws {
        try requireOffscreenRendering()
        let model = heldMatrixFixture(count: 4, displayCount: 2)
        model.workspacePreferences = nil
        let before = model.settings
        var pins = 0
        let window = window(HeldWorkspaceWheelView(model: model, select: { _ in XCTFail("Reordering never switches Spaces") },
            keepOpen: { pins += 1 }), visible: false)
        window.appearance = NSAppearance(named: .darkAqua)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(400))
        func find(_ view: NSView) -> WheelInteractionSurface.CursorView? {
            if let tracker = view as? WheelInteractionSurface.CursorView { return tracker }
            return view.subviews.lazy.compactMap(find).first
        }
        let tracker = try XCTUnwrap(window.contentView.flatMap(find))
        let payload = try XCTUnwrap(tracker.beginDrag?(0))
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(pins, 1); XCTAssertEqual(model.settings, before)
        let point = HeldWorkspaceWheelLayout.labelPoint(index: 2, count: 4)
        let destination = tracker.convert(point, to: nil)
        let target = try XCTUnwrap(tracker.dropTarget(raw: payload.rawValue, at: destination))
        tracker.dropHovered?(2)
        try await Task.sleep(for: .milliseconds(150))
        try capture("wheel-drag-valid-target", window: window)
        XCTAssertTrue(tracker.receive?(target.sourceID, target.targetID, target.after) == true)
        tracker.endDrag?()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(model.settings.contextPlan.contexts.sorted { $0.order < $1.order }.map(\.id), ["work-1", "work-2", "work-0", "work-3"])
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, before.savedWorkspaces.bookmarks)
        XCTAssertFalse(model.isSwitching)
        try pressOffscreen("held-undo-connection", in: window)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(model.settings.contextPlan, before.contextPlan)
        // A second drag cancelled over the center changes nothing.
        _ = tracker.beginDrag?(1)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertNil(tracker.dropTarget(raw: tracker.activeDrag?.rawValue, at: tracker.convert(NSPoint(x: 220, y: 220), to: nil)))
        tracker.endDrag?()
        XCTAssertEqual(model.settings.contextPlan, before.contextPlan)
        XCTAssertFalse(window.isVisible)
    }

    func testWheelDragKeepsSourceAcrossPagesOffscreen() async throws {
        try requireOffscreenRendering()
        let model = heldMatrixFixture(count: 10, displayCount: 2)
        model.workspacePreferences = nil
        let before = model.settings
        let window = window(HeldWorkspaceWheelView(model: model,
            select: { _ in XCTFail("Page navigation and drag never switch Spaces") }), visible: false)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(400))
        func find(_ view: NSView) -> WheelInteractionSurface.CursorView? {
            if let tracker = view as? WheelInteractionSurface.CursorView { return tracker }
            return view.subviews.lazy.compactMap(find).first
        }
        let tracker = try XCTUnwrap(window.contentView.flatMap(find))
        let payload = try XCTUnwrap(tracker.beginDrag?(0))
        try await Task.sleep(for: .milliseconds(100))
        try pressOffscreen("wheel-next-page", in: window)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(tracker.columnIDs, ["work-8", "work-9"])
        XCTAssertEqual(tracker.activeDrag, payload)
        let point = tracker.convert(HeldWorkspaceWheelLayout.labelPoint(index: 1, count: 2), to: nil)
        let target = try XCTUnwrap(tracker.dropTarget(raw: payload.rawValue, at: point))
        XCTAssertTrue(tracker.receive?(target.sourceID, target.targetID, target.after) == true)
        tracker.endDrag?()
        XCTAssertEqual(model.settings.contextPlan.contexts.sorted { $0.order < $1.order }.last?.id, "work-0")
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, before.savedWorkspaces.bookmarks)
        XCTAssertTrue(model.undoSavedWorkspaceChange())
        XCTAssertEqual(model.settings.contextPlan, before.contextPlan)
        XCTAssertFalse(window.isVisible)
    }

}
