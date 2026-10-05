import AppKit
import SidebyCore
import SidebyUI

struct HeldWorkspaceColumn: Identifiable {
    enum Bookmark: Equatable { case persistent(String), runtime(UInt64), unavailable }
    let id: String
    let name: String
    let bookmarks: [String: Bookmark]
    let cells: [String: String]
    let desktopLabels: [String: String]

    @MainActor init(context: ContextDefinition, displayIDs: [String], model: SidebyAppModel) {
        id = context.id
        name = context.name
        var marks: [String: Bookmark] = [:]
        var cells: [String: String] = [:]
        var labels: [String: String] = [:]
        let strings = model.connectionCopy
        for displayID in displayIDs {
            guard let index = context.spaceIndex(for: displayID) else { continue }
            marks[displayID] = Self.bookmark(displayID: displayID, index: index, model: model)
            cells[displayID] = model.workspaceDesktopName(displayID: displayID, spaceIndex: index) ?? strings.spacePosition(index)
            labels[displayID] = strings.spacePosition(index)
        }
        bookmarks = marks
        self.cells = cells
        desktopLabels = labels
    }

    @MainActor private static func bookmark(displayID: String, index: Int, model: SidebyAppModel) -> Bookmark {
        if let keys = model.workspaceLastObservedSpaceKeys[displayID], keys.indices.contains(index) { return .persistent(keys[index]) }
        if let ids = model.workspaceLastObservedSpaceIDs[displayID], ids.indices.contains(index) { return .runtime(ids[index]) }
        return .unavailable
    }

    @MainActor func stillMatches(model: SidebyAppModel, displayIDs: [String]) -> Bool {
        guard let current = model.settings.contextPlan.contexts.first(where: { $0.id == id }) else { return false }
        let active = Set(model.displayLayout.displays.map(\.id)).intersection(model.selectedDisplayIDs)
        guard active == Set(displayIDs) else { return false }
        let latest = HeldWorkspaceColumn(context: current, displayIDs: displayIDs, model: model)
        return !bookmarks.isEmpty && !bookmarks.values.contains(.unavailable) && bookmarks == latest.bookmarks
    }
}

struct HeldWorkspaceSnapshot {
    let displayIDs: [String]
    let displayNames: [String: String]
    let columns: [HeldWorkspaceColumn]
    let initialColumnID: String?

    @MainActor init(model: SidebyAppModel, previousColumnID: String? = nil) {
        let active = Set(model.displayLayout.displays.map(\.id)).intersection(model.selectedDisplayIDs)
        let orderedDisplayIDs = WorkspaceTablePresentation.displayIDs(connected: model.displayLayout.displays.map(\.id),
            remembered: [], assigned: [], order: model.settings.displayRowOrder, includeDisconnected: false).filter { active.contains($0) }
        displayIDs = orderedDisplayIDs
        displayNames = Dictionary(uniqueKeysWithValues: orderedDisplayIDs.map { ($0, model.displayName(for: $0)) })
        columns = model.settings.contextPlan.contexts.sorted { $0.order < $1.order }
            .map { HeldWorkspaceColumn(context: $0, displayIDs: orderedDisplayIDs, model: model) }
        let preferred = model.verifiedCurrentWorkspaceID ?? previousColumnID
        initialColumnID = columns.first { $0.id == preferred }?.id ?? columns.first?.id
    }
}

enum HeldMatrixPanelLayout {
    static let columnWidth: CGFloat = 174
    static let rowHeight: CGFloat = 56
    static let headerHeight: CGFloat = 64
    static let labelWidth: CGFloat = 120

    static func size(columns: Int, displays: Int, visibleFrame: NSRect, accessoryHeight: CGFloat = 0, editing: Bool = false) -> NSSize {
        let width = max(editing ? 820 : 440, 162 + CGFloat(max(1, columns)) * (columnWidth + 6))
        let tableHeight = min(360, headerHeight + CGFloat(max(1, displays)) * rowHeight + 14)
        let height = editing ? 680 : max(280, 130 + tableHeight + accessoryHeight)
        return NSSize(width: min(width, 1040, max(1, visibleFrame.width - 32)),
                      height: min(height, max(1, visibleFrame.height - 48)))
    }

    static func origin(size: NSSize, pointer: NSPoint, visibleFrame: NSRect) -> NSPoint {
        let bounds = visibleFrame.insetBy(dx: 16, dy: 16)
        return NSPoint(x: max(bounds.minX, min(pointer.x - size.width / 2, bounds.maxX - size.width)),
                       y: max(bounds.minY, min(pointer.y - size.height + 62, bounds.maxY - size.height)))
    }
}

extension SidebyAppModel {
    static var heldMatrixConfigurationKey: String { "sideby.held-matrix-v1" }

    func loadHeldMatrixConfiguration() {
        if let data = workspacePreferences?.data(forKey: Self.heldMatrixConfigurationKey),
           let value = try? JSONDecoder().decode(HeldMatrixConfiguration.self, from: data) { heldMatrixConfiguration = value }
    }

    func startHeldMatrixInput() {
        if heldMatrixController == nil { heldMatrixController = HeldWorkspaceMatrixController(model: self) }
        heldMatrixShortcutError = heldMatrixController!.configure(heldMatrixConfiguration)
            ? nil : HeldMatrixStrings(language: settings.language).registrationFailed
    }

    @discardableResult func updateHeldMatrixConfiguration(_ value: HeldMatrixConfiguration) -> Bool {
        let copy = HeldMatrixStrings(language: settings.language)
        guard !value.isEnabled || HeldMatrixConfiguration.isValid(value.shortcut) else { heldMatrixShortcutError = copy.invalidShortcut; return false }
        if let controller = heldMatrixController, !controller.configure(value) {
            heldMatrixShortcutError = copy.registrationFailed
            return false
        }
        heldMatrixConfiguration = value
        heldMatrixShortcutError = nil
        if let data = try? JSONEncoder().encode(value) { workspacePreferences?.set(data, forKey: Self.heldMatrixConfigurationKey) }
        return true
    }

    func heldMatrixCanActivate(_ column: HeldWorkspaceColumn, displayIDs: [String]) -> Bool {
        isEnabled && canActivateContext && pendingContextCaptureAlignment == nil
            && hasSwitchingAccess && column.stillMatches(model: self, displayIDs: displayIDs)
            && isWorkspaceAssignmentAvailable(contextID: column.id)
    }
}
