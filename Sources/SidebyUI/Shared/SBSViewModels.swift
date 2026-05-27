import SidebyCore
import SwiftUI

@MainActor
public protocol SBSOnboardingViewModel: ObservableObject {
    var hasAccessibilityPermission: Bool { get }
    var hasSwitchingAccess: Bool { get }
    var permissionRequestFeedback: PermissionRequestFeedback? { get }
    var detectedGestureCount: Int { get }
    var displayCount: Int { get }

    func openSystemSettingsAccessibility()
    func openSystemSettingsAutomation()
    func requestSwitchingAccess()
    func skipGestureTest()
    func finish()
}
