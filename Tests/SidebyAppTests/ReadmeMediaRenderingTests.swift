import AppKit
import SwiftUI
import XCTest
import SidebyCore
import SidebySystem
import SidebyUI
@testable import SidebyApp

/// Offscreen production views, backed only by sample data and discarding stores.
/// No app launch, monitor connection, global input, permission request, or Space command.
@MainActor
final class ReadmeMediaRenderingTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    func testOffscreenOnboardingDefersNamesUntilExplicitRefreshWithoutChangingWorkOrProgress() async throws {
        let model = try makeModel(language: .english)
        let original = model.settings.contextPlan.contexts
        let progress = model.firstWorkProgress
        let names = model.workspaceDesktopNames
        model.workspaceDesktopNames = [:]
        model.workspaceNameSuggestionProvider = MediaNames(values: names)
        model.isSwitching = true
        let preferences = MemoryProductUIPreferences()
        preferences.onboardingStage = .workspaces
        let host = NSHostingView(rootView: onboarding(model, preferences).frame(width: 640, height: 700))
        let window = mount(host, size: .init(width: 640, height: 700), dark: false)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(200))
        await model.refreshVisibleConnections(force: true)
        XCTAssertTrue(model.workspaceDesktopNames.isEmpty, "Busy capture must defer name discovery")
        model.isSwitching = false
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertTrue(model.workspaceDesktopNames.isEmpty, "Offscreen media views must not start automatic title queries")
        // Rendering uses an explicit read. Visible-window polling has its own
        // native test; this offscreen fixture must not depend on WindowServer.
        await model.refreshVisibleConnections(force: true)
        XCTAssertEqual(model.workspaceDesktopName(displayID: "display-0", spaceIndex: 0), "Checkout.swift")
        XCTAssertEqual(model.workspaceDesktopName(displayID: "display-1", spaceIndex: 0), "Checkout API")
        XCTAssertNil(model.workspaceDesktopName(displayID: "display-1", spaceIndex: 99))
        XCTAssertEqual(model.settings.contextPlan.contexts, original)
        XCTAssertEqual(model.firstWorkProgress, progress)
        XCTAssertEqual(preferences.onboardingStage, .workspaces)
        XCTAssertNil(model.workspacePreferences)
    }

    func testRenderCurrentConnectionsMedia() async throws {
        guard ProcessInfo.processInfo.environment["SIDEBY_RENDER_MEDIA"] == "1" else {
            throw XCTSkip("Opt-in current connections documentation")
        }
        let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SIDEBY_MEDIA_OUTPUT"] ?? "/tmp/sideby-connections-media")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for language in [AppLanguage.english, .korean] {
            let suffix = language == .english ? "en" : "ko"
            let model = try makeModel(language: language)
            completeProgress(model)
            let original = try XCTUnwrap(model.workspaceObservationOverride?())
            let current = WorkspaceLayoutObservation(displays: original.displays.enumerated().map { offset, display in
                .init(displayID: display.displayID, spaceCount: display.spaceCount, currentSpaceIndex: offset == 0 ? 0 : 1)
            }, spaceIDsByDisplayID: original.spaceIDsByDisplayID, spaceKeysByDisplayID: original.spaceKeysByDisplayID)
            model.workspaceObservationOverride = { current }
            model.refreshWorkspaceStatus()
            XCTAssertNotNil(model.addCurrentConnection())
            try await render(ProductSettingsView(model: model,
                navigation: ProductUINavigation(preferences: MemoryProductUIPreferences()), canCheckForUpdates: false,
                actions: .init(checkForUpdates: {}, openOnboarding: {}, finishAssignmentReview: {})),
                to: output.appendingPathComponent("sideby-connections-settings-\(suffix).png"), width: 1040, height: 640, dark: false)
            try await render(HeldWorkspaceWheelView(model: model, select: { _ in }, persistent: true),
                to: output.appendingPathComponent("sideby-connections-\(suffix).png"),
                width: 472, height: 568, dark: true, transparent: true,
                hoverPoint: HeldWorkspaceWheelLayout.labelPoint(index: 1, count: 3))
            let empty = try makeModel(language: language, workspaceCount: 0)
            let preferences = MemoryProductUIPreferences()
            preferences.onboardingStage = .workspaces
            try await render(onboarding(empty, preferences),
                to: output.appendingPathComponent("sideby-connections-onboarding-\(suffix).png"), width: 680, height: 640, dark: false)
        }
    }

    func testRenderConnectionTutorialScenes() async throws {
        guard ProcessInfo.processInfo.environment["SIDEBY_RENDER_TUTORIAL"] == "1" else {
            throw XCTSkip("Opt-in tutorial scenes with fictional data")
        }
        let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SIDEBY_MEDIA_OUTPUT"] ?? "/tmp/sideby-tutorial-scenes")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for language in [AppLanguage.korean, .english] {
            let lang = language == .korean ? "ko" : "en"
            let setup = try makeModel(language: language, workspaceCount: 0)
            completeProgress(setup)
            let setupObservation = try XCTUnwrap(setup.workspaceObservationOverride?())
            func setupScene(_ name: String) async throws {
                try await render(ProductSettingsView(model: setup,
                    navigation: ProductUINavigation(preferences: MemoryProductUIPreferences()), canCheckForUpdates: false,
                    actions: .init(checkForUpdates: {}, openOnboarding: {}, finishAssignmentReview: {})),
                    to: output.appendingPathComponent("\(name)-\(lang).png"), width: 1040, height: 640, dark: false)
            }
            try await setupScene("setup-empty")
            let firstSpace = try XCTUnwrap(setupObservation.spaceKeysByDisplayID["display-0"]?.first)
            XCTAssertTrue(setup.setCurrentConnection(displayID: "display-0", key: firstSpace, contextID: nil))
            let newConnection = try XCTUnwrap(setup.settings.contextPlan.contexts.first)
            XCTAssertEqual(newConnection.displayIDs.count, 1)
            try await setupScene("setup-first")
            let secondSpace = try XCTUnwrap(setupObservation.spaceKeysByDisplayID["display-1"]?.first)
            XCTAssertTrue(setup.setCurrentConnection(displayID: "display-1", key: secondSpace, contextID: newConnection.id))
            XCTAssertEqual(setup.settings.contextPlan.contexts.count, 1)
            XCTAssertEqual(setup.settings.contextPlan.contexts.first?.displayIDs.count, 2)
            XCTAssertEqual(setup.workspaceObservationOverride?(), setupObservation)
            try await setupScene("setup-complete")
            let model = try makeModel(language: language)
            completeProgress(model)
            func settings(_ name: String) async throws {
                try await render(ProductSettingsView(model: model,
                    navigation: ProductUINavigation(preferences: MemoryProductUIPreferences()), canCheckForUpdates: false,
                    actions: .init(checkForUpdates: {}, openOnboarding: {}, finishAssignmentReview: {})),
                    to: output.appendingPathComponent("\(name)-\(lang).png"), width: 1040, height: 640, dark: false)
            }
            func quick(_ name: String) async throws {
                try await render(HeldWorkspaceMatrixView(model: model, snapshot: .init(model: model), select: { _ in }, persistent: true),
                    to: output.appendingPathComponent("\(name)-\(lang).png"), width: 720, height: 420, dark: true)
            }
            try await settings("drag-before")
            let key = try XCTUnwrap(model.settings.savedWorkspaces.bookmarks["checkout"]?["display-1"])
            let target = try XCTUnwrap(model.settings.savedWorkspaces.bookmarks["review"]?["display-1"])
            XCTAssertTrue(model.transferCurrentConnection(.init(displayID: "display-1", key: key),
                from: "checkout", to: "review", expectedDestinationKey: target, copying: false))
            try await settings("drag-after")
            model.workspaceSaveMessage = nil
            try await quick("capture-before")
            let captured = try XCTUnwrap(model.addCurrentConnection())
            XCTAssertEqual(model.settings.contextPlan.contexts.first(where: { $0.id == captured })?.name,
                "Checkout.swift / Checkout API")
            try await quick("capture-after")
            // Simulated observation for explanatory media; never send an actual Space command.
            let original = try XCTUnwrap(model.workspaceObservationOverride?())
            let review = WorkspaceLayoutObservation(displays: original.displays.map { display in
                .init(displayID: display.displayID, spaceCount: display.spaceCount,
                      currentSpaceIndex: display.displayID == "display-0" ? 1 : 0)
            }, spaceIDsByDisplayID: original.spaceIDsByDisplayID, spaceKeysByDisplayID: original.spaceKeysByDisplayID)
            model.workspaceObservationOverride = { review }; model.refreshWorkspaceStatus()
            try await quick("switch-review")
            model.workspaceObservationOverride = { original }; model.refreshWorkspaceStatus()
            try await quick("switch-return")
        }
    }

    func testFirstConnectionKeepsSourceCardsAndDropTargetsInPlace() async throws {
        NSApplication.shared.perform(NSSelectorFromString("accessibilitySetValue:forAttribute:"),
            with: NSNumber(value: true), with: "AXEnhancedUserInterface")
        for language in [AppLanguage.korean, .english] {
            for size in [NSSize(width: 760, height: 560), NSSize(width: 1040, height: 640)] {
                let model = try makeModel(language: language, workspaceCount: 0)
                completeProgress(model)
                let beforeObservation = model.workspaceObservationOverride?()
                let host = NSHostingView(rootView: ProductSettingsView(model: model,
                    navigation: ProductUINavigation(preferences: MemoryProductUIPreferences()), canCheckForUpdates: false,
                    actions: .init(checkForUpdates: {}, openOnboarding: {}, finishAssignmentReview: {}))
                    .frame(width: size.width, height: size.height))
                let window = mount(host, size: size, dark: false)
                defer { window.close() }
                try await Task.sleep(for: .milliseconds(200))
                func rectangle(_ identifier: String) throws -> NSRect {
                    func find(_ object: NSObject) -> NSObject? {
                        if object.responds(to: NSSelectorFromString("accessibilityIdentifier")),
                           object.perform(NSSelectorFromString("accessibilityIdentifier"))?.takeUnretainedValue() as? String == identifier { return object }
                        if object.responds(to: NSSelectorFromString("accessibilityChildren")),
                           let children = object.perform(NSSelectorFromString("accessibilityChildren"))?.takeUnretainedValue() as? [NSObject] {
                            for child in children { if let found = find(child) { return found } }
                        }
                        return nil
                    }
                    host.layoutSubtreeIfNeeded()
                    let element = try XCTUnwrap(find(host) as? any NSAccessibilityElementProtocol, identifier)
                    return window.convertFromScreen(element.accessibilityFrame())
                }
                let sourceIDs = ["connection-source-display-0-0", "connection-source-display-1-0", "current-connections-table"]
                let sources = try sourceIDs.map(rectangle)
                let emptyCells = try (0..<2).map { try rectangle("connection-cell-new-display-\($0)") }
                let windowFrame = window.frame
                XCTAssertTrue(host.bounds.contains(try rectangle("connections-start")), "The alternative start action remains reachable")
                XCTAssertTrue(model.setCurrentConnection(displayID: "display-0", key: "sample-display-0-desktop-0", contextID: nil))
                let id = try XCTUnwrap(model.settings.contextPlan.contexts.first?.id)
                try await Task.sleep(for: .milliseconds(200))
                for (identifier, before) in zip(sourceIDs, sources) {
                    XCTAssertEqual(try rectangle(identifier), before, "First connection must not shift \(identifier), \(language), \(size)")
                }
                for display in 0..<2 {
                    XCTAssertEqual(try rectangle("connection-cell-\(id)-display-\(display)"), emptyCells[display])
                }
                XCTAssertTrue(model.setCurrentConnection(displayID: "display-1", key: "sample-display-1-desktop-0", contextID: id))
                try await Task.sleep(for: .milliseconds(150))
                for (identifier, before) in zip(sourceIDs, sources) { XCTAssertEqual(try rectangle(identifier), before) }
                XCTAssertEqual(window.frame, windowFrame)
                XCTAssertEqual(model.workspaceObservationOverride?(), beforeObservation)
                XCTAssertTrue(model.undoSavedWorkspaceChange())
                XCTAssertTrue(model.undoSavedWorkspaceChange())
                try await Task.sleep(for: .milliseconds(150))
                XCTAssertTrue(model.settings.contextPlan.contexts.isEmpty)
                for (identifier, before) in zip(sourceIDs, sources) { XCTAssertEqual(try rectangle(identifier), before) }
                XCTAssertNil(model.workspacePreferences)
                XCTAssertFalse(model.isSwitching)
            }
        }
    }

    func testRenderFastConnectionTutorialScenes() async throws {
        guard ProcessInfo.processInfo.environment["SIDEBY_RENDER_TUTORIAL_FAST"] == "1" else {
            throw XCTSkip("Opt-in expanded tutorial using fictional data only")
        }
        NSApplication.shared.perform(NSSelectorFromString("accessibilitySetValue:forAttribute:"),
            with: NSNumber(value: true), with: "AXEnhancedUserInterface")
        let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SIDEBY_MEDIA_OUTPUT"]
            ?? "/tmp/sideby-tutorial-fast-scenes")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for language in [AppLanguage.korean, .english] {
            let lang = language == .korean ? "ko" : "en"
            func settings(_ model: SidebyAppModel, _ name: String) async throws {
                try await render(ProductSettingsView(model: model,
                    navigation: ProductUINavigation(preferences: MemoryProductUIPreferences()), canCheckForUpdates: false,
                    actions: .init(checkForUpdates: {}, openOnboarding: {}, finishAssignmentReview: {})),
                    to: output.appendingPathComponent("\(name)-\(lang).png"), width: 1040, height: 640, dark: false)
            }
            func quick(_ model: SidebyAppModel, _ name: String, hoverID: String? = nil) async throws {
                let columns = model.settings.contextPlan.contexts.sorted { $0.order < $1.order }
                let point = hoverID.flatMap { id in columns.firstIndex { $0.id == id } }
                    .map { HeldWorkspaceWheelLayout.labelPoint(index: $0, count: columns.count) }
                try await render(HeldWorkspaceWheelView(model: model, select: { _ in }, persistent: true),
                    to: output.appendingPathComponent("\(name)-\(lang).png"), width: 472, height: 568, dark: true,
                    transparent: true, hoverPoint: point)
            }
            let setup = try makeModel(language: language, workspaceCount: 0)
            completeProgress(setup)
            let setupObservation = try XCTUnwrap(setup.workspaceObservationOverride?())
            try await quick(setup, "wheel-empty")
            try await settings(setup, "setup-empty")
            XCTAssertTrue(setup.setCurrentConnection(displayID: "display-0", key: "sample-display-0-desktop-0", contextID: nil))
            let firstID = try XCTUnwrap(setup.settings.contextPlan.contexts.first?.id)
            try await settings(setup, "setup-first")
            XCTAssertTrue(setup.setCurrentConnection(displayID: "display-1", key: "sample-display-1-desktop-0", contextID: firstID))
            try await settings(setup, "setup-complete")
            XCTAssertEqual(setup.settings.contextPlan.contexts.count, 1)
            XCTAssertEqual(setup.settings.contextPlan.contexts.first?.displayIDs.count, 2)
            XCTAssertEqual(setup.workspaceObservationOverride?(), setupObservation)

            let model = try makeModel(language: language)
            completeProgress(model)
            let initial = model.settings.savedWorkspaces.bookmarks
            let original = try XCTUnwrap(model.workspaceObservationOverride?())
            // A fictional current arrangement that differs from both columns.
            let current = WorkspaceLayoutObservation(displays: original.displays.map {
                .init(displayID: $0.displayID, spaceCount: $0.spaceCount, currentSpaceIndex: $0.displayID == "display-0" ? 0 : 1)
            }, spaceIDsByDisplayID: original.spaceIDsByDisplayID, spaceKeysByDisplayID: original.spaceKeysByDisplayID)
            model.workspaceObservationOverride = { current }; model.refreshWorkspaceStatus(); model.workspaceSaveMessage = nil
            try await quick(model, "capture-before")
            let captured = try XCTUnwrap(model.addCurrentConnection())
            let target = try XCTUnwrap(model.settings.contextPlan.contexts.first { $0.id == captured })
            XCTAssertEqual(target.name, "Checkout.swift / Checkout preview")
            try await quick(model, "capture-after")
            let beforeEditing = model.settings.savedWorkspaces.bookmarks
            model.workspaceObservationOverride = { original }; model.refreshWorkspaceStatus()
            // Explain the everyday shortcut before the editing gestures. Observations
            // remain fictional; this render never sends a real Space switch command.
            XCTAssertEqual(model.verifiedCurrentWorkspaceID, "checkout")
            try await quick(model, "work-before", hoverID: "review")
            let earlyReview = WorkspaceLayoutObservation(displays: original.displays.map {
                .init(displayID: $0.displayID, spaceCount: $0.spaceCount, currentSpaceIndex: 1)
            }, spaceIDsByDisplayID: original.spaceIDsByDisplayID, spaceKeysByDisplayID: original.spaceKeysByDisplayID)
            model.workspaceObservationOverride = { earlyReview }; model.refreshWorkspaceStatus()
            XCTAssertEqual(model.verifiedCurrentWorkspaceID, "review")
            try await quick(model, "work-after")
            model.workspaceObservationOverride = { original }; model.refreshWorkspaceStatus()
            XCTAssertEqual(model.verifiedCurrentWorkspaceID, "checkout")
            XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, beforeEditing)
            model.workspaceObservationOverride = { current }; model.refreshWorkspaceStatus()
            try await settings(model, "drag-before")
            let source = WorkspaceDesktopReference(displayID: "display-1", key: "sample-display-1-desktop-0")
            XCTAssertTrue(model.transferCurrentConnection(source, from: "checkout", to: "review",
                expectedDestinationKey: "sample-display-1-desktop-1", copying: false))
            try await settings(model, "drag-after")
            XCTAssertTrue(model.undoSavedWorkspaceChange())
            XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, beforeEditing)
            try await settings(model, "undo-after")
            XCTAssertTrue(model.transferCurrentConnection(source, from: "checkout", to: "review",
                expectedDestinationKey: "sample-display-1-desktop-1", copying: true))
            XCTAssertEqual(model.settings.savedWorkspaces.bookmarks["checkout"], initial["checkout"])
            XCTAssertEqual(model.settings.savedWorkspaces.bookmarks["review"]?["display-1"], source.key)
            try await settings(model, "copy-after")
            XCTAssertEqual(model.workspaceObservationOverride?(), current, "Editing never switches real or fixture Spaces")
            model.workspaceSaveMessage = nil
            try await quick(model, "rename-matrix", hoverID: captured)

            try await render(ConnectionNameEditor(model: model, target: target, close: {}),
                to: output.appendingPathComponent("rename-before-\(lang).png"), width: 360, height: 160, dark: true)
            let name = language == .korean ? "집중 작업" : "Focus"
            XCTAssertTrue(model.renameCurrentConnection(captured, originalName: target.name, name: name))
            let renamed = try XCTUnwrap(model.settings.contextPlan.contexts.first { $0.id == captured })
            try await render(ConnectionNameEditor(model: model, target: renamed, close: {}),
                to: output.appendingPathComponent("rename-after-\(lang).png"), width: 360, height: 160, dark: true)
            model.workspaceSaveMessage = nil
            try await quick(model, "renamed", hoverID: captured)
            XCTAssertTrue(model.deleteSavedWorkspace(captured))
            try await quick(model, "delete-after")
            XCTAssertTrue(model.undoSavedWorkspaceChange())
            try await quick(model, "delete-undo", hoverID: captured)
            let review = WorkspaceLayoutObservation(displays: original.displays.map {
                .init(displayID: $0.displayID, spaceCount: $0.spaceCount, currentSpaceIndex: $0.displayID == "display-0" ? 1 : 0)
            }, spaceIDsByDisplayID: original.spaceIDsByDisplayID, spaceKeysByDisplayID: original.spaceKeysByDisplayID)
            model.workspaceObservationOverride = { review }; model.refreshWorkspaceStatus()
            XCTAssertEqual(model.verifiedCurrentWorkspaceID, "review")
            try await quick(model, "switch-review")
            model.workspaceObservationOverride = { current }; model.refreshWorkspaceStatus()
            XCTAssertEqual(model.verifiedCurrentWorkspaceID, captured)
            try await quick(model, "switch-return")
            XCTAssertFalse(model.isSwitching)
            XCTAssertNil(model.workspacePreferences)
            try JSONSerialization.data(withJSONObject: ["setupID": firstID, "capturedID": captured], options: [.prettyPrinted])
                .write(to: output.appendingPathComponent("identifiers-\(lang).json"))
        }
    }

    func testRenderReadmeMedia() async throws {
        guard ProcessInfo.processInfo.environment["SIDEBY_RENDER_MEDIA"] == "1" else {
            throw XCTSkip("Opt-in deterministic README media generation")
        }
        let output = ProcessInfo.processInfo.environment["SIDEBY_MEDIA_OUTPUT"].map { URL(fileURLWithPath: $0) }
            ?? root.appendingPathComponent("docs/images")
        let work = ProcessInfo.processInfo.environment["SIDEBY_MEDIA_WORK_DIR"].map { URL(fileURLWithPath: $0) }
            ?? root.appendingPathComponent(".build/readme-media")
        let evidence = work.appendingPathComponent("review")
        let intermediates = work.appendingPathComponent("native")
        for directory in [output, evidence, intermediates] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        for language in [AppLanguage.english, .korean] {
            let suffix = language == .english ? "en" : "ko"
            let model = try makeModel(language: language)
            completeProgress(model)
            model.workspaceHistory.recordSuccessfulVisit(contextID: "review")
            model.workspaceHistory.recordSuccessfulVisit(contextID: "checkout")
            let menu = ProductFloatingMenuPanelView(model: model,
                actions: .init(route: { _ in }, quit: {}))
            try await render(menu, to: output.appendingPathComponent("sideby-context-capture-\(suffix).png"),
                             width: 680, height: 640, dark: true)
            let individual = try makeModel(language: language)
            try await render(WorkspaceLibraryView(model: individual,
                navigation: ProductUINavigation(preferences: MemoryProductUIPreferences()), finish: {}),
                to: output.appendingPathComponent("sideby-setup-editor-\(suffix).png"), width: 900, height: 660, dark: false)
            let composer = try makeModel(language: language)
            let settings = WorkspaceLibraryView(model: composer,
                navigation: ProductUINavigation(preferences: MemoryProductUIPreferences()), startsInOverview: true, finish: {})
            try await render(settings, to: output.appendingPathComponent("sideby-settings-workspaces-\(suffix).png"),
                             width: 980, height: 720, dark: false)
            XCTAssertTrue(composer.assignWorkspaceComposer(
                .init(displayID: "display-1", key: "sample-display-1-desktop-1"), to: "checkout"))
            try await render(settings, to: intermediates.appendingPathComponent("composer-assigned-\(suffix).png"),
                             width: 980, height: 720, dark: false)
            XCTAssertTrue(composer.commitWorkspaceComposer())
            try await render(settings, to: intermediates.appendingPathComponent("composer-saved-\(suffix).png"),
                             width: 980, height: 720, dark: false)
            let empty = try makeModel(language: language, workspaceCount: 0)
            try await render(SavedWorkspaceBrowser(model: empty).padding(18),
                to: intermediates.appendingPathComponent("empty-\(suffix).png"), width: 680, height: 560, dark: true)
            empty.workspaceSaveDraft = empty.prepareWorkspaceSave()
            empty.workspaceSaveDraft?.name = language == .english ? "Checkout" : "결제 개발"
            try await render(WorkspaceSaveView(model: empty, finish: { _ in }),
                to: output.appendingPathComponent("sideby-save-workspace-\(suffix).png"), width: 530, height: 480, dark: false)
            let first = try makeModel(language: language, workspaceCount: 1)
            try await render(SavedWorkspaceBrowser(model: first).padding(18),
                to: intermediates.appendingPathComponent("first-\(suffix).png"), width: 680, height: 560, dark: true)
            let review = try makeModel(language: language, currentIndex: 1)
            try await render(SavedWorkspaceBrowser(model: review).padding(18),
                to: intermediates.appendingPathComponent("review-\(suffix).png"), width: 680, height: 560, dark: true)
            // Continue the walkthrough with the edited setup and matching sample
            // observation, so the final matrix preserves the saved connection.
            let previous = try XCTUnwrap(composer.workspaceLatestObservation)
            let returned = WorkspaceLayoutObservation(displays: previous.displays.map {
                .init(displayID: $0.displayID, spaceCount: $0.spaceCount,
                      currentSpaceIndex: $0.displayID == "display-1" ? 1 : 0)
            }, spaceIDsByDisplayID: previous.spaceIDsByDisplayID,
               spaceKeysByDisplayID: previous.spaceKeysByDisplayID)
            composer.workspaceObservationOverride = { returned }
            composer.workspaceLatestObservation = returned
            composer.workspaceObservedDisplays = returned.displays
            composer.verifiedCurrentWorkspaceID = "checkout"
            completeProgress(composer)
            composer.workspaceHistory.recordSuccessfulVisit(contextID: "review")
            composer.workspaceHistory.recordSuccessfulVisit(contextID: "checkout")
            try await render(SavedWorkspaceBrowser(model: composer).padding(18),
                to: intermediates.appendingPathComponent("return-\(suffix).png"), width: 680, height: 560, dark: true)
            let preferences = MemoryProductUIPreferences()
            preferences.onboardingStage = .workspaces
            try await render(onboarding(empty, preferences),
                to: output.appendingPathComponent("sideby-onboarding-saved-workspaces-\(suffix).png"), width: 640, height: 760, dark: false)
            // Opposite appearance and one-display coverage stay outside public assets.
            try await render(onboarding(model, preferences),
                to: evidence.appendingPathComponent("roundtrip-\(suffix)-dark.png"), width: 640, height: 520, dark: true)
            let single = try makeModel(language: language, displayCount: 1)
            let singlePreferences = MemoryProductUIPreferences()
            singlePreferences.onboardingStage = .displays
            try await render(onboarding(single, singlePreferences),
                to: evidence.appendingPathComponent("single-display-\(suffix).png"), width: 640, height: 520, dark: false)
            singlePreferences.onboardingStage = .workspaces
            single.workspaceDesktopNames = [:]
            try await render(onboarding(single, singlePreferences),
                to: evidence.appendingPathComponent("unnamed-desktops-\(suffix)-dark.png"), width: 640, height: 700, dark: true)
            let longNames = try makeModel(language: language)
            longNames.workspaceDesktopNames["display-0"]?[0] = "CheckoutPaymentConfirmationView.swift — Order validation and payment confirmation"
            let longPreferences = MemoryProductUIPreferences()
            longPreferences.onboardingStage = .workspaces
            try await render(onboarding(longNames, longPreferences),
                to: evidence.appendingPathComponent("long-content-name-\(suffix).png"), width: 640, height: 700, dark: false)
            if language == .english {
                try await render(WorkspaceMatrixView(model: model, compact: true).padding(18)
                    .background(NativeSurfaceStyle.windowBackground),
                    to: intermediates.appendingPathComponent("matrix.png"), width: 700, height: 310, dark: true)
            }
            XCTAssertNil(model.workspacePreferences)
            XCTAssertNil(model.workspaceNameSuggestionProvider)
            XCTAssertFalse(model.isSwitching)
        }
    }

    func testRenderUsabilityReview() async throws {
        guard ProcessInfo.processInfo.environment["SIDEBY_RENDER_USABILITY"] == "1" else {
            throw XCTSkip("Opt-in local usability review fixtures")
        }
        let output = URL(fileURLWithPath: "/tmp/sideby-usability-review.noindex")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for language in [AppLanguage.english, .korean] {
            let suffix = language == .english ? "en" : "ko"
            for dark in [false, true] {
                let appearance = dark ? "dark" : "light"
                for all in [false, true] {
                    let model = try makeModel(language: language)
                    let nav = ProductUINavigation(preferences: MemoryProductUIPreferences())
                    try await render(WorkspaceLibraryView(model: model, navigation: nav, startsInOverview: all, finish: {}),
                        to: output.appendingPathComponent("library-\(all ? "all" : "one")-\(suffix)-\(appearance).png"),
                        width: all ? 1040 : 900, height: 660, dark: dark)
                    XCTAssertFalse(model.isSwitching)
                    XCTAssertFalse(model.hasWorkspaceComposerChanges)
                }
                for stage in [ProductOnboardingStage.preparation, .workspaces, .roundTrip] {
                    let model = try makeModel(language: language, workspaceCount: stage == .workspaces ? 0 : 1)
                    let preferences = MemoryProductUIPreferences()
                    preferences.onboardingStage = stage
                    try await render(onboarding(model, preferences),
                        to: output.appendingPathComponent("guide-\(stage)-\(suffix)-\(appearance).png"),
                        width: 680, height: 660, dark: dark)
                    XCTAssertFalse(model.firstWorkProgress.isComplete)
                    XCTAssertFalse(model.isSwitching)
                }
            }
            let model = try makeModel(language: language)
            let nav = ProductUINavigation(preferences: MemoryProductUIPreferences())
            try await render(WorkspaceLibraryView(model: model, navigation: nav, finish: {}),
                to: output.appendingPathComponent("library-small-\(suffix).png"), width: 760, height: 560, dark: false)
            let preferences = MemoryProductUIPreferences()
            preferences.onboardingStage = .workspaces
            try await render(onboarding(model, preferences), to: output.appendingPathComponent("guide-small-\(suffix).png"),
                width: 560, height: 480, dark: false)
            let empty = try makeModel(language: language, workspaceCount: 0)
            try await render(WorkspaceLibraryView(model: empty, navigation: nav, finish: {}),
                to: output.appendingPathComponent("library-empty-\(suffix).png"), width: 900, height: 660, dark: false)
            try await render(ProductSettingsView(model: model, navigation: nav, canCheckForUpdates: false,
                actions: .init(checkForUpdates: {}, openOnboarding: {}, finishAssignmentReview: {})),
                to: output.appendingPathComponent("settings-\(suffix).png"), width: 680, height: 600, dark: false)
        }
    }

    private func makeModel(language: AppLanguage, displayCount: Int = 2, workspaceCount: Int = 2, currentIndex: Int = 0) throws -> SidebyAppModel {
        let fixture = try JSONDecoder().decode(MediaFixture.self,
            from: Data(contentsOf: root.appendingPathComponent("docs/media/demo-data.json")))
        let displays = Array(fixture.displays.prefix(displayCount))
        let ids = displays.map(\.id)
        var settings = AppSettings.default
        settings.language = language
        settings.contextPlan = .init(contexts: fixture.workspaces.prefix(workspaceCount).enumerated().map { index, workspace in
            .init(id: workspace.id, order: index + 1, name: language == .english ? workspace.en : workspace.ko,
                  displaySpaceIndexes: Dictionary(uniqueKeysWithValues: ids.map { ($0, index) }))
        }, currentContextID: fixture.workspaces[currentIndex].id)
        settings.displaySelection = .init(hasInitialized: true, selectedDisplayIDs: Set(ids),
            knownDisplayNames: Dictionary(uniqueKeysWithValues: displays.map { ($0.id, $0.name) }))
        settings.displayRowOrder = ids
        let observation = displays.map { InstantCaptureDisplay(displayID: $0.id, spaceCount: fixture.workspaces.count, currentSpaceIndex: currentIndex) }
        let model = SidebyAppModel(testSettings: settings, selectedDisplayIDs: Set(ids),
            selectedDisplaySpaces: { observation }, postEventAccessGranted: true)
        model.displayLayout = .init(displays: displays.enumerated().map { index, display in
            .init(id: display.id, name: display.name, isPrimary: index == 0, isBuiltin: display.builtin,
                  frame: .init(x: Double(index * 1920), y: index == 0 ? 300 : 0, width: 1920, height: 1080))
        })
        let spaceIDs = Dictionary(uniqueKeysWithValues: ids.enumerated().map { index, id in
            (id, fixture.workspaces.indices.map { UInt64(100 * (index + 1) + $0) })
        })
        let keys = Dictionary(uniqueKeysWithValues: ids.map { id in
            (id, fixture.workspaces.indices.map { "sample-" + id + "-desktop-" + String($0) })
        })
        let layout = WorkspaceLayoutObservation(displays: observation, spaceIDsByDisplayID: spaceIDs, spaceKeysByDisplayID: keys)
        model.workspaceObservationOverride = { layout }
        model.workspaceSpaceIDsOverride = { spaceIDs }
        _ = model.initializeSavedWorkspaceLibrary(layout)
        model.workspaceLatestObservation = layout
        model.workspaceObservedDisplays = observation
        model.workspaceLastObservedSpaceIDs = spaceIDs
        model.workspaceDesktopNameSpaceIDs = spaceIDs
        model.workspaceDesktopNames = Dictionary(uniqueKeysWithValues: displays.enumerated().map { displayIndex, display in
            (display.id, Dictionary(uniqueKeysWithValues: fixture.workspaces.enumerated().map { index, workspace in
                (index, workspace.desktops[displayIndex].title)
            }))
        })
        _ = model.workspaceConnectionSession.confirm(spaceIDsByDisplayID: spaceIDs)
        model.workspaceConnectionStatus = .ready
        model.verifiedCurrentWorkspaceID = workspaceCount == 0 ? nil : fixture.workspaces[currentIndex].id
        model.permissionState = .granted
        return model
    }

    private func completeProgress(_ model: SidebyAppModel) {
        model.firstWorkProgress = .init()
        for id in ["checkout", "review", "checkout"] { model.firstWorkProgress.recordSuccessfulVisit(contextID: id) }
    }

    private func onboarding(_ model: SidebyAppModel, _ preferences: MemoryProductUIPreferences) -> some View {
        ProductOnboardingView(model: model, presentation: ProductOnboardingPresentation(preferences: preferences),
            preferences: preferences, actions: .init(close: {}, finishToDaily: {}, openInputSettings: {}, openWorkspaceSettings: { _, _ in }))
    }

    private func mount<V: View>(_ host: NSHostingView<V>, size: NSSize, dark: Bool) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        host.setFrameSize(size)
        host.layoutSubtreeIfNeeded()
        return window
    }

    private func render<V: View>(_ view: V, to url: URL, width: CGFloat, height: CGFloat, dark: Bool,
                                 transparent: Bool = false, hoverPoint: CGPoint? = nil) async throws {
        let pixels = NSSize(width: width * 2, height: height * 2)
        let host = NSHostingView(rootView: view.frame(width: width, height: height)
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.controlActiveState, .key)
            .environment(\.displayScale, 2)
            .scaleEffect(2, anchor: .topLeading)
            .frame(width: pixels.width, height: pixels.height, alignment: .topLeading))
        let window = mount(host, size: pixels, dark: dark)
        if transparent { window.backgroundColor = .clear; window.isOpaque = false; window.hasShadow = false }
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(transparent ? 650 : 180))
        host.layoutSubtreeIfNeeded()
        if let hoverPoint {
            // Dispatch only to this isolated view's cursor tracker. No global
            // input, real desktop capture, or application activation is needed.
            func tracker(_ view: NSView) -> NSView? {
                if String(describing: type(of: view)) == "CursorView" { return view }
                return view.subviews.lazy.compactMap(tracker).first
            }
            let cursor = NSCursor.current
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved,
                location: NSPoint(x: (16 + hoverPoint.x) * 2, y: pixels.height - (8 + hoverPoint.y) * 2),
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
            try XCTUnwrap(tracker(host)).mouseMoved(with: event)
            cursor.set()
            try await Task.sleep(for: .milliseconds(100))
            host.layoutSubtreeIfNeeded()
        }
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * 2), pixelsHigh: Int(height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = pixels
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            host.cacheDisplay(in: host.bounds, to: bitmap)
        }
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
        if ProcessInfo.processInfo.environment["SIDEBY_RENDER_TUTORIAL_FAST"] == "1" {
            var frames: [String: [String: CGFloat]] = [:]
            func visit(_ object: NSObject) {
                if object.responds(to: NSSelectorFromString("accessibilityIdentifier")),
                   let id = object.perform(NSSelectorFromString("accessibilityIdentifier"))?.takeUnretainedValue() as? String,
                   let element = object as? any NSAccessibilityElementProtocol {
                    let local = window.convertFromScreen(element.accessibilityFrame())
                    frames[id] = ["x": local.minX, "y": pixels.height - local.maxY, "w": local.width, "h": local.height]
                }
                if object.responds(to: NSSelectorFromString("accessibilityChildren")),
                   let children = object.perform(NSSelectorFromString("accessibilityChildren"))?.takeUnretainedValue() as? [NSObject] {
                    children.forEach(visit)
                }
            }
            visit(host)
            try JSONSerialization.data(withJSONObject: frames, options: [.prettyPrinted, .sortedKeys])
                .write(to: url.deletingPathExtension().appendingPathExtension("json"))
        }
        print("Rendered production view: \(url.lastPathComponent) · \(bitmap.pixelsWide)×\(bitmap.pixelsHigh)")
    }
}

private struct MediaFixture: Decodable {
    struct Display: Decodable { let id: String; let name: String; let builtin: Bool }
    struct Desktop: Decodable { let title: String }
    struct Workspace: Decodable { let id: String; let en: String; let ko: String; let desktops: [Desktop] }
    let displays: [Display]
    let workspaces: [Workspace]
}

private struct MediaNames: SpaceNameSuggestionProviding {
    let values: [String: [Int: String]]
    func names(for layout: DisplayLayout, spaceIDsByDisplayID: [String: [UInt64]]) -> [String: [Int: String]] { values }
}
