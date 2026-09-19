import AppKit
import SwiftUI
import XCTest
import SidebyCore
import SidebyUI
@testable import SidebyApp

@MainActor
final class WorkspaceSettingsNativeEvidenceTests: XCTestCase {
    private let output = ProcessInfo.processInfo.environment["SIDEBY_NATIVE_EVIDENCE_OUTPUT"].map { URL(fileURLWithPath: $0) }
        ?? URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(".build/native-settings-evidence")

    func testRenderProductionSettingsAndSharedSelector() async throws {
        guard ProcessInfo.processInfo.environment["SIDEBY_NATIVE_EVIDENCE"] == "1" else {
            throw XCTSkip("Opt-in native settings evidence")
        }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for dark in [false, true] {
            for (width, count, rows) in [(700, 2, 7), (840, 1, 8), (840, 2, 4), (700, 4, 8)] {
                let model = makeModel(displayCount: count, rows: rows)
                let navigation = ProductUINavigation(preferences: MemoryProductUIPreferences())
                let view = settings(model, navigation)
                try await render(view, name: "settings-\(width)-\(count)displays-\(dark ? "dark" : "light")", width: CGFloat(width), height: 620, dark: dark)
                XCTAssertNil(model.contextCaptureSession)
                XCTAssertFalse(model.isSwitching)
            }
        }
        for dark in [false, true] {
            let model = makeModel(displayCount: 4, rows: 8, offline: true, longNames: true)
            let navigation = ProductUINavigation(preferences: MemoryProductUIPreferences())
            try await render(settings(model, navigation), name: "settings-long-offline-highcontrast-\(dark ? "dark" : "light")", width: 700, height: 892, dark: dark, highContrast: true,
                afterMount: { navigation.openSettings(.init(pane: .workspaces, contextID: "task-6", displayID: "offline")) })
        }
        let tall = makeModel(displayCount: 2, rows: 7)
        try await render(settings(tall, ProductUINavigation(preferences: MemoryProductUIPreferences())), name: "settings-700x892-two-displays-dark", width: 700, height: 892, dark: true)
        tall.workspaceHistory.recordSuccessfulVisit(contextID: "task-1")
        tall.workspaceHistory.recordSuccessfulVisit(contextID: "task-0")
        tall.workspaceRebuildBackup = .init(plan: tall.settings.contextPlan, nameOrigins: [:],
                                           identity: .init(plan: tall.settings.contextPlan, spaceKeys: [:]))
        let menu = ProductFloatingMenuPanelView(model: tall, onSwitchQueued: { _ in }, actions: .init(route: { _ in }, quit: {}), initialExpansion: .default)
        try await render(menu, name: "menu-matrix-dark", width: 680, height: 620, dark: true)
        let single = makeModel(displayCount: 1, rows: 3)
        let singleMenu = ProductFloatingMenuPanelView(model: single, onSwitchQueued: { _ in }, actions: .init(route: { _ in }, quit: {}), initialExpansion: .default)
        try await render(singleMenu, name: "menu-matrix-single-light", width: 680, height: 620, dark: false)
        let model = makeModel(displayCount: 2, rows: 4)
        let preferences = MemoryProductUIPreferences()
        preferences.onboardingStage = .displays
        let onboarding = ProductOnboardingView(model: model, presentation: ProductOnboardingPresentation(preferences: preferences), preferences: preferences,
            actions: .init(close: {}, finishToDaily: {}, openInputSettings: {}, openWorkspaceSettings: { _, _ in }))
        try await render(onboarding, name: "onboarding-shared-selector-dark", width: 640, height: 600, dark: true)
        model.workspaceObservationOverride = { nil }
        model.workspaceConnectionStatus = .unavailable(["display-0", "display-1"])
        try await render(settings(model, ProductUINavigation(preferences: MemoryProductUIPreferences())), name: "settings-read-failure-dark", width: 700, height: 620, dark: true)
        model.displayLayout = .init(displays: [.init(id: "display-0", name: "Unknown position", isPrimary: true, isBuiltin: true)])
        try await render(settings(model, ProductUINavigation(preferences: MemoryProductUIPreferences())), name: "settings-unknown-geometry-light", width: 700, height: 620, dark: false)
    }

    private func settings(_ model: SidebyAppModel, _ navigation: ProductUINavigation) -> some View {
        ProductSettingsView(model: model, navigation: navigation, canCheckForUpdates: false,
            actions: .init(checkForUpdates: {}, openOnboarding: {}, finishAssignmentReview: {}))
    }

    private func makeModel(displayCount: Int, rows: Int, offline: Bool = false, longNames: Bool = false) -> SidebyAppModel {
        let ids = (0..<displayCount).map { "display-\($0)" }
        var settings = AppSettings.default
        settings.language = .korean
        settings.contextPlan = .init(contexts: (0..<rows).map { index in
            .init(id: "task-\(index)", order: index + 1,
                name: longNames ? "고객 \(index + 1) 결제 시스템 개발과 외부 서비스 연동 오류 원인 확인과 수정 검토" : ["결제 개발", "PR 리뷰", "서비스 운영", "디자인 검토", "고객 지원", "문서 작성", "다음 작업", "배포 준비"][index % 8],
                displaySpaceIndexes: Dictionary(uniqueKeysWithValues: (ids + (offline ? ["offline"] : [])).map { ($0, index) }))
        }, currentContextID: "task-0")
        settings.displaySelection = .init(hasInitialized: true, selectedDisplayIDs: Set(ids + (offline ? ["offline"] : [])),
            knownDisplayNames: offline ? ["offline": "기억하고 있는 세로 모니터"] : [:])
        let observations = ids.map { InstantCaptureDisplay(displayID: $0, spaceCount: rows, currentSpaceIndex: 0) }
        let model = SidebyAppModel(testSettings: settings, selectedDisplayIDs: Set(ids), selectedDisplaySpaces: { observations }, postEventAccessGranted: true)
        model.workspacePreferences = nil
        model.displayLayout = .init(displays: ids.enumerated().map { offset, id in
            .init(id: id, name: longNames ? "Studio Display \(offset + 1) — Customer Experience Development and Production Review Monitor" : offset == 0 ? "MacBook Pro" : "Studio Display \(offset)", isPrimary: offset == 0, isBuiltin: offset == 0,
                frame: .init(x: Double(offset * 1920), y: offset == 0 ? 720 : 0, width: offset == 2 ? 1080 : 1920, height: offset == 2 ? 1920 : 1080))
        })
        model.permissionState = .granted
        let spaceIDs = Dictionary(uniqueKeysWithValues: ids.enumerated().map { offset, id in (id, (0..<rows).map { UInt64(100 * (offset + 1) + $0) }) })
        model.workspaceSpaceIDsOverride = { spaceIDs }
        model.workspaceDesktopNameSpaceIDs = spaceIDs
        model.workspaceLastObservedSpaceIDs = spaceIDs
        model.workspaceObservedDisplays = observations
        model.workspaceDesktopNames = Dictionary(uniqueKeysWithValues: ids.enumerated().map { offset, id in
            let labels = offset == 0 ? ["Payment.swift", "Checkout PR #142", "운영 대시보드", "Figma"]
                : ["API 문서", "리뷰 실행 화면", "배포 로그", "디자인 가이드"]
            return (id, Dictionary(uniqueKeysWithValues: (0..<max(0, rows - 1)).map { index in
                (index, longNames ? "고객 결제 시스템 연동 오류를 확인하기 위한 긴 데스크탑 창 제목 \(index + 1)" : labels[index % labels.count])
            }))
        })
        _ = model.workspaceConnectionSession.confirm(spaceIDsByDisplayID: spaceIDs)
        model.workspaceConnectionStatus = .ready
        model.verifiedCurrentWorkspaceID = "task-0"
        return model
    }

    private func render<V: View>(_ view: V, name: String, width: CGFloat, height: CGFloat, dark: Bool, highContrast: Bool = false, afterMount: () -> Void = {}) async throws {
        let host = NSHostingView(rootView: view.frame(width: width, height: height))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: highContrast ? (dark ? .accessibilityHighContrastDarkAqua : .accessibilityHighContrastAqua) : (dark ? .darkAqua : .aqua))
        window.contentView = host
        host.setFrameSize(NSSize(width: width, height: height))
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        afterMount()
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        if name.contains("offline") {
            var scrolls: [NSScrollView] = []
            func inspect(_ view: NSView) {
                if let scroll = view as? NSScrollView { scrolls.append(scroll) }
                view.subviews.forEach(inspect)
            }
            inspect(host)
            XCTAssertEqual(scrolls.count, 3, "One sidebar and exactly one table scroll owner per axis")
            XCTAssertTrue(scrolls.contains { $0.contentView.bounds.minX > 0 }, "Requested workspace column must be revealed")
            // The offline display is now a row. It may already fit vertically in the tall fixture.
        }
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent(name + ".png"))
        window.close()
        print("Production native fixture: \(name)")
    }
}
