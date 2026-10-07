import AppKit
import SwiftUI

extension SidebyAppModel {
    /// Only presentation data is read in the background; apply it on the main actor
    /// after checking that the same Spaces and displays still exist.
    func refreshVisibleConnections(force: Bool = false) async {
        guard !connectionContentRefreshInFlight, !isSwitching, contextCaptureSession == nil,
              pendingContextCaptureAlignment == nil else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if !force, let last = connectionContentRefreshTime, now - last < 1.5 { return }
        connectionContentRefreshTime = now
        refreshWorkspaceStatus()
        guard let provider = workspaceNameSuggestionProvider,
              let observation = workspaceObservation(includingUnselectedDisplays: true) else { return }
        let layout = displayLayout
        connectionContentRefreshInFlight = true
        defer { connectionContentRefreshInFlight = false }
        let names = await Task.detached(priority: .utility) {
            provider.names(for: layout, spaceIDsByDisplayID: observation.spaceIDsByDisplayID)
        }.value
        guard !Task.isCancelled, !isSwitching, contextCaptureSession == nil,
              pendingContextCaptureAlignment == nil, displayLayout == layout,
              workspaceObservation(includingUnselectedDisplays: true)?.spaceIDsByDisplayID == observation.spaceIDsByDisplayID else { return }
        if workspaceDesktopNames != names { workspaceDesktopNames = names }
        workspaceDesktopNameSpaceIDs = observation.spaceIDsByDisplayID
    }
}

/// Visible editors refresh themselves; hidden windows do no automatic title queries.
struct CurrentConnectionsLiveRefresh: NSViewRepresentable {
    let model: SidebyAppModel
    var paused: Bool
    var didRefresh: () -> Void

    func makeNSView(context: Context) -> RefreshView { RefreshView() }
    func updateNSView(_ view: RefreshView, context: Context) {
        view.model = model; view.paused = paused; view.didRefresh = didRefresh
    }

    final class RefreshView: NSView {
        weak var model: SidebyAppModel?
        var paused = false
        var didRefresh: (() -> Void)?
        private var loop: Task<Void, Never>?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            loop?.cancel(); loop = nil
            guard window != nil else { return }
            loop = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    if let view = self { await view.refreshIfVisible() } else { return }
                    do { try await Task.sleep(for: .seconds(2)) } catch { return }
                }
            }
        }
        func refreshIfVisible() async {
            guard !paused, let window, window.isVisible, window.occlusionState.contains(.visible),
                  !NSApp.isHidden, let model else { return }
            await model.refreshVisibleConnections()
            if !Task.isCancelled { didRefresh?() }
        }
        deinit { loop?.cancel() }
    }
}
