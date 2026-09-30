import SidebyCore
import SwiftUI

/// Shared read-and-move matrix. Assignment changes are staged in a single-workspace editor.
struct WorkspaceMatrixView: View {
    @ObservedObject var model: SidebyAppModel
    var compact = false
    var showsDisconnected = false
    var focusContextID: String?
    var focusDisplayID: String?

    var body: some View {
        SavedWorkspaceMatrix(model: model)
            .onAppear {
                if let focusContextID { model.workspaceSavedFocusID = focusContextID }
                model.loadWorkspaceNamesIfNeeded()
            }
            .onChange(of: focusContextID) { _, id in model.workspaceSavedFocusID = id }
    }
}
