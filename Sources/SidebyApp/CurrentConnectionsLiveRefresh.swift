import AppKit
import SwiftUI

extension SidebyAppModel {
    /// Only presentation data is read in the background; apply it on the main actor
    /// after checking that the same Spaces and displays still exist.
    @discardableResult
    func refreshVisibleConnections(force: Bool = false) async -> WorkspaceLayoutObservation? {
        guard !connectionContentRefreshInFlight, !isSwitching, contextCaptureSession == nil,
              pendingContextCaptureAlignment == nil else { return nil }
        let now = ProcessInfo.processInfo.systemUptime
        if !force, let last = connectionContentRefreshTime, now - last < 1.5 { return nil }
        connectionContentRefreshTime = now
        refreshWorkspaceStatus()
        let observation = workspaceObservation(includingUnselectedDisplays: true)
        guard let observation, let provider = workspaceNameSuggestionProvider else { return observation }
        let layout = displayLayout
        connectionContentRefreshInFlight = true
        defer { connectionContentRefreshInFlight = false }
        let names = await Task.detached(priority: .utility) {
            provider.names(for: layout, spaceIDsByDisplayID: observation.spaceIDsByDisplayID)
        }.value
        guard !Task.isCancelled, !isSwitching, contextCaptureSession == nil,
              pendingContextCaptureAlignment == nil, displayLayout == layout,
              let current = workspaceObservation(includingUnselectedDisplays: true),
              current.spaceIDsByDisplayID == observation.spaceIDsByDisplayID,
              current.spaceKeysByDisplayID == observation.spaceKeysByDisplayID else {
            connectionContentRefreshTime = nil
            return nil
        }
        if workspaceDesktopNames != names { workspaceDesktopNames = names }
        workspaceDesktopNameSpaceIDs = observation.spaceIDsByDisplayID
        return current
    }
}

/// Visible editors refresh themselves; hidden windows do no automatic title queries.
struct CurrentConnectionsLiveRefresh: NSViewRepresentable {
    let model: SidebyAppModel
    var paused: Bool
    var didRefresh: (WorkspaceLayoutObservation?) -> Void

    func makeNSView(context: Context) -> RefreshView { RefreshView() }
    func updateNSView(_ view: RefreshView, context: Context) {
        view.model = model; view.paused = paused; view.didRefresh = didRefresh
    }

    final class RefreshView: NSView {
        weak var model: SidebyAppModel?
        var paused = false
        var didRefresh: ((WorkspaceLayoutObservation?) -> Void)?
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
            let observation = await model.refreshVisibleConnections()
            if !Task.isCancelled { didRefresh?(observation) }
        }
        deinit { loop?.cancel() }
    }
}
