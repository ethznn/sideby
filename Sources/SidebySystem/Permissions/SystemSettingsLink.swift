import Foundation

public enum SystemSettingsLink {
    public static let root = URL(fileURLWithPath: "/System/Applications/System Settings.app")

    public static let accessibility = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!

    public static let automation = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
    )!
}
