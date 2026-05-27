import ApplicationServices
import SidebyCore

public struct AccessibilityPermissionService: PermissionServicing {
    public init() {}

    public var currentState: PermissionState {
        AXIsProcessTrusted() ? .granted : .denied
    }

    public func requestAccessPrompt() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
