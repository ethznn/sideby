import Foundation
import SidebyCore

/// Identity-only navigation. Opening this target is never an instruction to move Spaces.
struct ConnectionEditorRevealRequest: Equatable, Identifiable {
    let id: UUID
    let contextID: String
    let displayID: String?

    init(id: UUID = UUID(), contextID: String, displayID: String? = nil) {
        self.id = id; self.contextID = contextID; self.displayID = displayID
    }

    struct Resolution: Equatable {
        enum Kind: Equatable { case missingContext, connectionOnly, offlineDisplay, unreadableDisplay, pickableDisplay }
        let kind: Kind
        let canOpenPicker: Bool
    }

    func resolve(context: ContextDefinition?, connectedIDs: Set<String>, readableIDs: Set<String>,
                 canEdit: Bool) -> Resolution {
        let kind: Resolution.Kind
        if context?.id != contextID { kind = .missingContext }
        else if let displayID, context?.displayIDs.contains(displayID) == true {
            if !connectedIDs.contains(displayID) { kind = .offlineDisplay }
            else if !readableIDs.contains(displayID) { kind = .unreadableDisplay }
            else { kind = .pickableDisplay }
        } else { kind = .connectionOnly }
        // Exclusion from switching is intentionally not an editing restriction.
        return Resolution(kind: kind, canOpenPicker: kind == .pickableDisplay && canEdit)
    }
}

/// A late callback for an old request cannot dismiss or open a newer target's picker.
struct ConnectionRepairSession: Equatable {
    private(set) var target: ConnectionEditorRevealRequest?
    private(set) var pickerID: UUID?

    mutating func show(_ target: ConnectionEditorRevealRequest?) { self.target = target; pickerID = nil }
    mutating func dismiss(_ id: UUID) { if target?.id == id { show(nil) } }
    mutating func setPicker(_ presented: Bool, for id: UUID) {
        guard target?.id == id else { return }
        pickerID = presented ? id : nil
    }
    mutating func closePicker() { pickerID = nil }
}
