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

    func testOnboardingLoadsNamesAfterBusyCaptureWithoutChangingWorkOrProgress() async throws {
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
        XCTAssertTrue(model.workspaceDesktopNames.isEmpty, "Busy capture must defer name discovery")
        model.isSwitching = false
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(model.workspaceDesktopName(displayID: "display-0", spaceIndex: 0), "Checkout.swift")
        XCTAssertEqual(model.workspaceDesktopName(displayID: "display-1", spaceIndex: 0), "Checkout API")
        XCTAssertNil(model.workspaceDesktopName(displayID: "display-1", spaceIndex: 99))
        XCTAssertEqual(model.settings.contextPlan.contexts, original)
        XCTAssertEqual(model.firstWorkProgress, progress)
        XCTAssertEqual(preferences.onboardingStage, .workspaces)
        XCTAssertNil(model.workspacePreferences)
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
            let menu = ProductFloatingMenuPanelView(model: model, onSwitchQueued: { _ in },
                actions: .init(route: { _ in }, quit: {}), initialExpansion: .default)
            try await render(menu, to: output.appendingPathComponent("sideby-context-capture-\(suffix).png"),
                             width: 680, height: 640, dark: true)
            let settings = ProductSettingsView(model: model,
                navigation: ProductUINavigation(preferences: MemoryProductUIPreferences()), canCheckForUpdates: false,
                actions: .init(checkForUpdates: {}, openOnboarding: {}, finishAssignmentReview: {}))
            try await render(settings, to: output.appendingPathComponent("sideby-settings-workspaces-\(suffix).png"),
                             width: 840, height: 620, dark: false)
            let preferences = MemoryProductUIPreferences()
            preferences.onboardingStage = .workspaces
            model.firstWorkProgress = .init()
            try await render(onboarding(model, preferences),
                to: output.appendingPathComponent("sideby-onboarding-workspaces-\(suffix).png"), width: 640, height: 760, dark: false)
            preferences.onboardingStage = .roundTrip
            completeProgress(model)
            try await render(onboarding(model, preferences),
                to: output.appendingPathComponent("sideby-onboarding-roundtrip-\(suffix).png"), width: 640, height: 520, dark: false)
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

    private func makeModel(language: AppLanguage, displayCount: Int = 2) throws -> SidebyAppModel {
        let fixture = try JSONDecoder().decode(MediaFixture.self,
            from: Data(contentsOf: root.appendingPathComponent("docs/media/demo-data.json")))
        let displays = Array(fixture.displays.prefix(displayCount))
        let ids = displays.map(\.id)
        var settings = AppSettings.default
        settings.language = language
        settings.contextPlan = .init(contexts: fixture.workspaces.enumerated().map { index, workspace in
            .init(id: workspace.id, order: index + 1, name: language == .english ? workspace.en : workspace.ko,
                  displaySpaceIndexes: Dictionary(uniqueKeysWithValues: ids.map { ($0, index) }))
        }, currentContextID: "checkout")
        settings.displaySelection = .init(hasInitialized: true, selectedDisplayIDs: Set(ids),
            knownDisplayNames: Dictionary(uniqueKeysWithValues: displays.map { ($0.id, $0.name) }))
        settings.displayRowOrder = ids
        let observation = displays.map { InstantCaptureDisplay(displayID: $0.id, spaceCount: 2, currentSpaceIndex: 0) }
        let model = SidebyAppModel(testSettings: settings, selectedDisplayIDs: Set(ids),
            selectedDisplaySpaces: { observation }, postEventAccessGranted: true)
        model.displayLayout = .init(displays: displays.enumerated().map { index, display in
            .init(id: display.id, name: display.name, isPrimary: index == 0, isBuiltin: display.builtin,
                  frame: .init(x: Double(index * 1920), y: index == 0 ? 300 : 0, width: 1920, height: 1080))
        })
        let spaceIDs = Dictionary(uniqueKeysWithValues: ids.enumerated().map { index, id in
            (id, [UInt64(100 * (index + 1)), UInt64(100 * (index + 1) + 1)])
        })
        model.workspaceSpaceIDsOverride = { spaceIDs }
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
        model.verifiedCurrentWorkspaceID = "checkout"
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

    private func render<V: View>(_ view: V, to url: URL, width: CGFloat, height: CGFloat, dark: Bool) async throws {
        let pixels = NSSize(width: width * 2, height: height * 2)
        let host = NSHostingView(rootView: view.frame(width: width, height: height)
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.controlActiveState, .key)
            .environment(\.displayScale, 2)
            .scaleEffect(2, anchor: .topLeading)
            .frame(width: pixels.width, height: pixels.height, alignment: .topLeading))
        let window = mount(host, size: pixels, dark: dark)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(180))
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * 2), pixelsHigh: Int(height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = pixels
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
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
